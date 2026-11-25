///|
fn logon_message(seq : String) -> @moonfix.Message {
  @moonfix.message("FIX.4.4", [
    { tag: 35, value: "A", },
    { tag: 34, value: seq, },
    { tag: 98, value: "0", },
    { tag: 108, value: "30", },
  ])
}

///|
fn heartbeat_message(seq : String, id : String?) -> @moonfix.Message {
  let fields : Array[@moonfix.Field] = [
    { tag: 35, value: "0", },
    { tag: 34, value: seq, },
  ]
  match id {
    Some(value) => fields.push({ tag: 112, value, })
    None => ()
  }
  @moonfix.message("FIX.4.4", fields)
}

///|
test "session reducer establishes logon and answers test requests" {
  let state = match @moonfix.new_session_state("FIX.4.4", 1, 1) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  let established = match @moonfix.apply_inbound(state, logon_message("1")) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  assert_true(established.accepted)
  assert_true(established.state.status is @moonfix.Active)
  assert_eq(established.state.next_inbound_seq, 2)
  assert_eq(established.state.next_outbound_seq, 2)
  assert_true(established.actions[0] is @moonfix.SessionEstablished)
  let test_request = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "1", },
    { tag: 34, value: "2", },
    { tag: 112, value: "ping-1", },
  ])
  let answered = match @moonfix.apply_inbound(established.state, test_request) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  assert_eq(answered.state.next_inbound_seq, 3)
  assert_true(answered.actions[0] is @moonfix.SendMessage(_))
  let probe = match @moonfix.start_test_request(answered.state, "probe-1") {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  let pong = match
    @moonfix.apply_inbound(probe.state, heartbeat_message("3", Some("probe-1"))) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  assert_true(pong.state.pending_test_request is None)
}

///|
test "Logon ResetSeqNumFlag resets both directions before sequence checks" {
  let stale = match @moonfix.new_session_state("FIX.4.4", 13, 27) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  let reset_logon = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "A", },
    { tag: 34, value: "1", },
    { tag: 98, value: "0", },
    { tag: 108, value: "30", },
    { tag: 141, value: "Y", },
  ])
  let transition = match @moonfix.apply_inbound(stale, reset_logon) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  assert_eq(transition.state.next_inbound_seq, 2)
  assert_eq(transition.state.next_outbound_seq, 2)
  let response = match transition.actions[1] {
    @moonfix.SendMessage(message) => message
    _ => fail("Logon response must be sent after establishment")
  }
  assert_eq(response.fields[1].value, "1")
  assert_true(response.fields.any(f => f.tag == 141 && f.value == "Y"))
}

///|
test "Logon ResetSeqNumFlag rejects invalid and repeated values" {
  let state = match @moonfix.new_session_state("FIX.4.4", 1, 1) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  let invalid = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "A", },
    { tag: 34, value: "1", },
    { tag: 98, value: "0", },
    { tag: 108, value: "30", },
    { tag: 141, value: "X", },
  ])
  match @moonfix.apply_inbound(state, invalid) {
    Ok(_) => fail("ResetSeqNumFlag must be Y or N")
    Err(error) => assert_eq(error.tag, 141)
  }
  let duplicate = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "A", },
    { tag: 34, value: "1", },
    { tag: 98, value: "0", },
    { tag: 108, value: "30", },
    { tag: 141, value: "Y", },
    { tag: 141, value: "N", },
  ])
  match @moonfix.apply_inbound(state, duplicate) {
    Ok(_) => fail("ResetSeqNumFlag must not be repeated")
    Err(error) => assert_eq(error.tag, 141)
  }
}

///|
test "session reducer emits resend request for a gap without advancing inbound state" {
  let state = match @moonfix.new_session_state("FIX.4.4", 1, 1) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  let gap = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "A", },
    { tag: 34, value: "3", },
    { tag: 108, value: "30", },
  ])
  let transition = match @moonfix.apply_inbound(state, gap) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  assert_true(!transition.accepted)
  assert_eq(transition.state.next_inbound_seq, 1)
  assert_true(transition.actions[0] is @moonfix.SendMessage(_))
}

///|
test "session reducer ignores a valid duplicate and applies sequence reset" {
  let initial = match @moonfix.new_session_state("FIX.4.4", 1, 1) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  let state = match @moonfix.apply_inbound(initial, logon_message("1")) {
    Ok(value) => value.state
    Err(error) => fail(error.detail)
  }
  let duplicate = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "0", },
    { tag: 34, value: "1", },
    { tag: 43, value: "Y", },
    { tag: 122, value: "20261124-12:00:00", },
  ])
  let ignored = match @moonfix.apply_inbound(state, duplicate) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  assert_true(ignored.actions[0] is @moonfix.DuplicateIgnored(1))
  let reset = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "4", },
    { tag: 34, value: "2", },
    { tag: 36, value: "9", },
    { tag: 123, value: "Y", },
  ])
  let advanced = match @moonfix.apply_inbound(state, reset) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  assert_eq(advanced.state.next_inbound_seq, 9)
}

///|
test "reset mode ignores MsgSeqNum while gap fill follows session ordering" {
  let initial = match @moonfix.new_session_state("FIX.4.4", 1, 1) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  let active = match @moonfix.apply_inbound(initial, logon_message("1")) {
    Ok(value) => value.state
    Err(error) => fail(error.detail)
  }
  let reset = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "4", },
    { tag: 34, value: "40", },
    { tag: 36, value: "8", },
    { tag: 123, value: "N", },
  ])
  let reset_result = match @moonfix.apply_inbound(active, reset) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  assert_true(reset_result.accepted)
  assert_eq(reset_result.state.next_inbound_seq, 8)

  let gap_fill_gap = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "4", },
    { tag: 34, value: "40", },
    { tag: 36, value: "8", },
    { tag: 123, value: "Y", },
  ])
  let gap_result = match @moonfix.apply_inbound(active, gap_fill_gap) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  assert_true(!gap_result.accepted)
  assert_eq(gap_result.state.next_inbound_seq, 2)
  assert_true(gap_result.actions[0] is @moonfix.SendMessage(_))
}

///|
test "sequence reset rejects a NewSeqNo that does not move forward" {
  let initial = match @moonfix.new_session_state("FIX.4.4", 1, 1) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  let active = match @moonfix.apply_inbound(initial, logon_message("1")) {
    Ok(value) => value.state
    Err(error) => fail(error.detail)
  }
  let reset = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "4", },
    { tag: 34, value: "40", },
    { tag: 36, value: "2", },
  ])
  match @moonfix.apply_inbound(active, reset) {
    Ok(_) => fail("reset mode must advance beyond the next expected sequence")
    Err(error) => assert_true(error.kind is @moonfix.InvalidReset)
  }
}

///|
test "session reducer terminates on logout and rejects invalid logon heartbeat" {
  let state = match @moonfix.new_session_state("FIX.4.4", 1, 1) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  let invalid = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "A", },
    { tag: 34, value: "1", },
    { tag: 98, value: "0", },
    { tag: 108, value: "0", },
  ])
  match @moonfix.apply_inbound(state, invalid) {
    Ok(_) => fail("zero heartbeat must be rejected")
    Err(error) => assert_true(error.kind is @moonfix.InvalidSessionField)
  }
  let missing_encrypt_method = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "A", },
    { tag: 34, value: "1", },
    { tag: 108, value: "30", },
  ])
  match @moonfix.apply_inbound(state, missing_encrypt_method) {
    Ok(_) => fail("Logon without EncryptMethod must be rejected")
    Err(error) => {
      assert_true(error.kind is @moonfix.MissingSessionField)
      assert_eq(error.tag, 98)
    }
  }
  let unsupported_encrypt_method = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "A", },
    { tag: 34, value: "1", },
    { tag: 98, value: "1", },
    { tag: 108, value: "30", },
  ])
  match @moonfix.apply_inbound(state, unsupported_encrypt_method) {
    Ok(_) => fail("unsupported encrypted Logon must be rejected")
    Err(error) => {
      assert_true(error.kind is @moonfix.InvalidSessionField)
      assert_eq(error.tag, 98)
    }
  }
  let duplicate_encrypt_method = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "A", },
    { tag: 34, value: "1", },
    { tag: 98, value: "0", },
    { tag: 98, value: "0", },
    { tag: 108, value: "30", },
  ])
  match @moonfix.apply_inbound(state, duplicate_encrypt_method) {
    Ok(_) => fail("duplicate EncryptMethod must be rejected")
    Err(error) => assert_true(error.kind is @moonfix.InvalidSessionField)
  }
  let malformed_encrypt_method = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "A", },
    { tag: 34, value: "1", },
    { tag: 98, value: "none", },
    { tag: 108, value: "30", },
  ])
  match @moonfix.apply_inbound(state, malformed_encrypt_method) {
    Ok(_) => fail("non-numeric EncryptMethod must be rejected")
    Err(error) => assert_true(error.kind is @moonfix.InvalidSessionField)
  }
  let active = match @moonfix.apply_inbound(state, logon_message("1")) {
    Ok(value) => value.state
    Err(error) => fail(error.detail)
  }
  let logout = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "5", },
    { tag: 34, value: "2", },
  ])
  let ended = match @moonfix.apply_inbound(active, logout) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  assert_true(ended.state.status is @moonfix.Terminated)
  assert_true(ended.actions[0] is @moonfix.PeerLoggedOut)
}

///|
test "session reducer rejects a mismatched BeginString before consuming sequence" {
  let state = match @moonfix.new_session_state("FIX.4.4", 1, 1) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  let wrong_version = @moonfix.message("FIX.4.2", [
    { tag: 35, value: "A", },
    { tag: 34, value: "1", },
    { tag: 98, value: "0", },
    { tag: 108, value: "30", },
  ])
  match @moonfix.apply_inbound(state, wrong_version) {
    Ok(_) => fail("a different BeginString must not enter this session")
    Err(error) => {
      assert_true(error.kind is @moonfix.InvalidSessionField)
      assert_eq(error.tag, 8)
    }
  }
  assert_eq(state.next_inbound_seq, 1)
}

///|
test "send_logout emits a sequenced Logout and terminates local state" {
  let initial = match @moonfix.new_session_state("FIX.4.4", 1, 1) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  let active = match @moonfix.apply_inbound(initial, logon_message("1")) {
    Ok(value) => value.state
    Err(error) => fail(error.detail)
  }
  let transition = match
    @moonfix.send_logout(active, text=Some("maintenance")) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  assert_true(transition.state.status is @moonfix.Terminated)
  assert_eq(transition.state.next_outbound_seq, active.next_outbound_seq + 1)
  let logout = match transition.actions[0] {
    @moonfix.SendMessage(message) => message
    _ => fail("send_logout must produce a Logout message")
  }
  assert_eq(logout.fields[0].value, "5")
  assert_eq(logout.fields[1].value, active.next_outbound_seq.to_string())
  assert_eq(logout.fields[2].tag, 58)
  assert_eq(logout.fields[2].value, "maintenance")
}

///|
test "send_logout rejects inactive sessions and empty reason text" {
  let initial = match @moonfix.new_session_state("FIX.4.4", 1, 1) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  match @moonfix.send_logout(initial) {
    Ok(_) => fail("Logout must require an active session")
    Err(error) => assert_true(error.kind is @moonfix.InvalidTransition)
  }
  let active = match @moonfix.apply_inbound(initial, logon_message("1")) {
    Ok(value) => value.state
    Err(error) => fail(error.detail)
  }
  match @moonfix.send_logout(active, text=Some("")) {
    Ok(_) => fail("provided empty reason text must be rejected")
    Err(error) => assert_eq(error.tag, 58)
  }
}

///|
test "session reducer rejects repeated control fields" {
  let initial = match @moonfix.new_session_state("FIX.4.4", 1, 1) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  let active = match @moonfix.apply_inbound(initial, logon_message("1")) {
    Ok(value) => value.state
    Err(error) => fail(error.detail)
  }
  let ambiguous_duplicate = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "0", },
    { tag: 34, value: "1", },
    { tag: 43, value: "Y", },
    { tag: 122, value: "20261125-12:00:00", },
    { tag: 122, value: "20261125-12:00:01", },
  ])
  match @moonfix.apply_inbound(active, ambiguous_duplicate) {
    Ok(_) => fail("duplicate OrigSendingTime must not be accepted as a replay")
    Err(error) => {
      assert_true(error.kind is @moonfix.InvalidSessionField)
      assert_eq(error.tag, 122)
    }
  }
  let duplicate_resend_range = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "2", },
    { tag: 34, value: "2", },
    { tag: 7, value: "1", },
    { tag: 7, value: "2", },
    { tag: 16, value: "0", },
  ])
  match @moonfix.apply_inbound(active, duplicate_resend_range) {
    Ok(_) => fail("duplicate ResendRequest range fields must be rejected")
    Err(error) => assert_eq(error.tag, 7)
  }
}
