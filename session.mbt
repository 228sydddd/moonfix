///|
/// Local lifecycle state; this reducer performs no I/O or clock reads.
pub(all) enum SessionStatus {
  AwaitingLogon
  Active
  Terminated
}

///|
pub(all) struct SessionState {
  begin_string : String
  status : SessionStatus
  next_inbound_seq : Int
  next_outbound_seq : Int
  heartbeat_seconds : Int
  pending_test_request : String?
}

///|
pub(all) enum SessionAction {
  SendMessage(Message)
  DeliverApplication(Message)
  DuplicateIgnored(Int)
  SessionEstablished
  PeerLoggedOut
  ResendRequested(Int, Int)
  SequenceAdvanced(Int)
  PeerRejected(Int?)
}

///|
pub(all) enum SessionErrorKind {
  MissingSessionField
  InvalidSessionField
  UnexpectedSequence
  InvalidTransition
  InvalidReset
}

///|
pub(all) struct SessionError {
  kind : SessionErrorKind
  tag : Int
  detail : String
}

///|
pub(all) struct SessionTransition {
  state : SessionState
  accepted : Bool
  actions : Array[SessionAction]
}

///|
pub fn new_session_state(
  begin_string : String,
  next_inbound_seq : Int,
  next_outbound_seq : Int,
) -> Result[SessionState, SessionError] {
  if begin_string.length() == 0 ||
    next_inbound_seq <= 0 ||
    next_outbound_seq <= 0 {
    return Err({
      kind: InvalidSessionField,
      tag: 0,
      detail: "begin string and initial sequence numbers must be valid",
    })
  }
  Ok({
    begin_string,
    status: AwaitingLogon,
    next_inbound_seq,
    next_outbound_seq,
    heartbeat_seconds: 0,
    pending_test_request: None,
  })
}

///|
/// Start an active-session liveness probe and remember the ID to match on Heartbeat.
pub fn start_test_request(
  state : SessionState,
  request_id : String,
) -> Result[SessionTransition, SessionError] {
  if !(state.status is Active) || request_id.length() == 0 {
    return Err(
      session_error(
        InvalidTransition,
        112,
        "TestRequest needs an active session and a nonempty ID",
      ),
    )
  }
  let (request, next_outbound) = make_send_action(state, "1", [
    { tag: 112, value: request_id, },
  ])
  let next = with_sequences(
    state,
    state.next_inbound_seq,
    next_outbound,
    Active,
    state.heartbeat_seconds,
    Some(request_id),
  )
  Ok(session_transition(next, true, [request]))
}

///|
/// Send Logout and terminate the local session, optionally including Text (58).
pub fn send_logout(
  state : SessionState,
  text? : String? = None,
) -> Result[SessionTransition, SessionError] {
  if !(state.status is Active) {
    return Err(
      session_error(InvalidTransition, 35, "Logout requires an active session"),
    )
  }
  let extra : Array[Field] = []
  match text {
    None => ()
    Some(value) if value.length() > 0 => extra.push({ tag: 58, value, })
    Some(_) =>
      return Err(
        session_error(InvalidSessionField, 58, "Logout Text cannot be empty"),
      )
  }
  let (action, next_outbound) = make_send_action(state, "5", extra)
  let next = with_sequences(
    state,
    state.next_inbound_seq,
    next_outbound,
    Terminated,
    state.heartbeat_seconds,
    None,
  )
  Ok(session_transition(next, true, [action]))
}

///|
fn session_error(
  kind : SessionErrorKind,
  tag : Int,
  detail : String,
) -> SessionError {
  { kind, tag, detail, }
}

///|
fn session_field(message : Message, tag : Int) -> String? {
  for field in message.fields {
    if field.tag == tag {
      return Some(field.value)
    }
  }
  None
}

///|
fn session_int(message : Message, tag : Int) -> Int? {
  match session_field(message, tag) {
    Some(value) => parse_length(value)
    None => None
  }
}

///|
fn session_type(message : Message) -> String? {
  session_field(message, 35)
}

///|
fn with_sequences(
  state : SessionState,
  inbound : Int,
  outbound : Int,
  status : SessionStatus,
  heartbeat : Int,
  pending : String?,
) -> SessionState {
  {
    begin_string: state.begin_string,
    status,
    next_inbound_seq: inbound,
    next_outbound_seq: outbound,
    heartbeat_seconds: heartbeat,
    pending_test_request: pending,
  }
}

///|
fn outgoing(
  state : SessionState,
  msg_type : String,
  extra : Array[Field],
) -> (Message, Int) {
  let fields : Array[Field] = [
    { tag: 35, value: msg_type, },
    { tag: 34, value: state.next_outbound_seq.to_string(), },
  ]
  for field in extra {
    fields.push(field)
  }
  (message(state.begin_string, fields), state.next_outbound_seq + 1)
}

///|
fn make_send_action(
  state : SessionState,
  msg_type : String,
  extra : Array[Field],
) -> (SessionAction, Int) {
  let (response, next) = outgoing(state, msg_type, extra)
  (SendMessage(response), next)
}

///|
fn session_transition(
  state : SessionState,
  accepted : Bool,
  actions : Array[SessionAction],
) -> SessionTransition {
  { state, accepted, actions, }
}

///|
/// Apply one inbound FIX message and return its deterministic state transition.
/// A sequence gap emits a ResendRequest and leaves the inbound sequence unchanged.
pub fn apply_inbound(
  state : SessionState,
  input : Message,
) -> Result[SessionTransition, SessionError] {
  if state.status is Terminated {
    return Err(
      session_error(
        InvalidTransition,
        35,
        "cannot process messages after session termination",
      ),
    )
  }
  if input.begin_string != state.begin_string {
    return Err(
      session_error(
        InvalidSessionField,
        8,
        "message BeginString does not match the configured session version",
      ),
    )
  }
  if number_of_tag(input.fields, 34) != 1 {
    return Err(
      session_error(
        MissingSessionField,
        34,
        "message must contain exactly one MsgSeqNum",
      ),
    )
  }
  if number_of_tag(input.fields, 35) != 1 {
    return Err(
      session_error(
        MissingSessionField,
        35,
        "message must contain exactly one MsgType",
      ),
    )
  }
  let msg_type = match session_type(input) {
    Some(value) => value
    None =>
      return Err(session_error(MissingSessionField, 35, "MsgType is missing"))
  }
  let control_tags : Array[Int] = [43, 122]
  match msg_type {
    "A" => {
      control_tags.push(98)
      control_tags.push(108)
      control_tags.push(141)
    }
    "0" | "1" => control_tags.push(112)
    "2" => {
      control_tags.push(7)
      control_tags.push(16)
    }
    "4" => {
      control_tags.push(36)
      control_tags.push(123)
    }
    "5" => control_tags.push(58)
    _ => ()
  }
  for tag in control_tags {
    if number_of_tag(input.fields, tag) > 1 {
      return Err(
        session_error(
          InvalidSessionField,
          tag,
          "session control fields must not be repeated",
        ),
      )
    }
  }
  let seq = match session_int(input, 34) {
    Some(value) if value > 0 => value
    _ =>
      return Err(
        session_error(
          InvalidSessionField,
          34,
          "MsgSeqNum must be a positive integer",
        ),
      )
  }
  let reset_logon = if msg_type == "A" {
    let reset_count = number_of_tag(input.fields, 141)
    if reset_count > 1 {
      return Err(
        session_error(
          InvalidSessionField,
          141,
          "Logon must not repeat ResetSeqNumFlag",
        ),
      )
    }
    match session_field(input, 141) {
      None | Some("N") => false
      Some("Y") => {
        if seq != 1 {
          return Err(
            session_error(
              InvalidReset,
              141,
              "ResetSeqNumFlag Logon must use sequence number 1",
            ),
          )
        }
        true
      }
      Some(_) =>
        return Err(
          session_error(
            InvalidSessionField,
            141,
            "ResetSeqNumFlag must be Y or N",
          ),
        )
    }
  } else {
    false
  }
  if msg_type == "4" {
    let gap_fill = match session_field(input, 123) {
      Some("Y") => true
      Some("N") | None => false
      Some(_) =>
        return Err(
          session_error(InvalidSessionField, 123, "GapFillFlag must be Y or N"),
        )
    }
    if !gap_fill {
      if state.status is AwaitingLogon {
        return Err(
          session_error(
            InvalidTransition,
            35,
            "SequenceReset requires an established session",
          ),
        )
      }
      let new_seq = match session_int(input, 36) {
        Some(value) if value > state.next_inbound_seq => value
        _ =>
          return Err(
            session_error(
              InvalidReset,
              36,
              "Reset-mode NewSeqNo must exceed the next expected sequence",
            ),
          )
      }
      let next = with_sequences(
        state,
        new_seq,
        state.next_outbound_seq,
        state.status,
        state.heartbeat_seconds,
        state.pending_test_request,
      )
      return Ok(session_transition(next, true, [SequenceAdvanced(new_seq)]))
    }
  }
  if !reset_logon && seq < state.next_inbound_seq {
    let possible_duplicate = session_field(input, 43) == Some("Y")
    let original_time_present = session_field(input, 122) is Some(_)
    if possible_duplicate && original_time_present {
      return Ok(session_transition(state, false, [DuplicateIgnored(seq)]))
    }
    return Err(
      session_error(
        UnexpectedSequence,
        34,
        "message sequence is older than the next expected value",
      ),
    )
  }
  if !reset_logon && seq > state.next_inbound_seq {
    let (request, next_outbound) = outgoing(state, "2", [
      { tag: 7, value: state.next_inbound_seq.to_string(), },
      { tag: 16, value: (seq - 1).to_string(), },
    ])
    let next = with_sequences(
      state,
      state.next_inbound_seq,
      next_outbound,
      state.status,
      state.heartbeat_seconds,
      state.pending_test_request,
    )
    return Ok(session_transition(next, false, [SendMessage(request)]))
  }
  if msg_type != "A" && state.status is AwaitingLogon {
    return Err(
      session_error(
        InvalidTransition,
        35,
        "Logon must establish the session before other messages",
      ),
    )
  }
  let next_inbound = if reset_logon { 2 } else { seq + 1 }
  match msg_type {
    "A" => {
      if state.status is Active {
        return Err(
          session_error(InvalidTransition, 35, "Logon is already complete"),
        )
      }
      let encrypt_method_count = number_of_tag(input.fields, 98)
      if encrypt_method_count == 0 {
        return Err(
          session_error(
            MissingSessionField,
            98,
            "Logon must contain exactly one EncryptMethod",
          ),
        )
      }
      if encrypt_method_count > 1 {
        return Err(
          session_error(
            InvalidSessionField,
            98,
            "Logon must not repeat EncryptMethod",
          ),
        )
      }
      match session_int(input, 98) {
        Some(0) => ()
        Some(_) =>
          return Err(
            session_error(
              InvalidSessionField,
              98,
              "only EncryptMethod NONE_OTHER (0) is supported",
            ),
          )
        None =>
          return Err(
            session_error(
              InvalidSessionField,
              98,
              "EncryptMethod must be a nonnegative integer",
            ),
          )
      }
      let heartbeat = match session_int(input, 108) {
        Some(value) if value > 0 && value <= 86_400 => value
        _ =>
          return Err(
            session_error(
              InvalidSessionField,
              108,
              "Logon HeartBtInt must be between 1 and 86400",
            ),
          )
      }
      let initial_outbound = if reset_logon {
        1
      } else {
        state.next_outbound_seq
      }
      let base = with_sequences(
        state,
        next_inbound,
        initial_outbound,
        Active,
        heartbeat,
        None,
      )
      let reply_fields : Array[Field] = [
        { tag: 98, value: "0", },
        { tag: 108, value: heartbeat.to_string(), },
      ]
      if reset_logon {
        reply_fields.push({ tag: 141, value: "Y", })
      }
      let (reply, next_outbound) = outgoing(base, "A", reply_fields)
      let next = with_sequences(
        base,
        next_inbound,
        next_outbound,
        Active,
        heartbeat,
        None,
      )
      Ok(
        session_transition(next, true, [SessionEstablished, SendMessage(reply)]),
      )
    }
    "0" => {
      let pending = match state.pending_test_request {
        Some(request_id) if session_field(input, 112) == Some(request_id) =>
          None
        other => other
      }
      let next = with_sequences(
        state,
        next_inbound,
        state.next_outbound_seq,
        state.status,
        state.heartbeat_seconds,
        pending,
      )
      Ok(session_transition(next, true, []))
    }
    "1" => {
      let request_id = match session_field(input, 112) {
        Some(value) => value
        None =>
          return Err(
            session_error(
              MissingSessionField,
              112,
              "TestRequest requires TestReqID",
            ),
          )
      }
      let base = with_sequences(
        state,
        next_inbound,
        state.next_outbound_seq,
        state.status,
        state.heartbeat_seconds,
        state.pending_test_request,
      )
      let (reply, next_outbound) = make_send_action(base, "0", [
        { tag: 112, value: request_id, },
      ])
      let next = with_sequences(
        base,
        next_inbound,
        next_outbound,
        base.status,
        base.heartbeat_seconds,
        base.pending_test_request,
      )
      Ok(session_transition(next, true, [reply]))
    }
    "2" => {
      let begin_seq = match session_int(input, 7) {
        Some(value) if value > 0 => value
        _ =>
          return Err(
            session_error(
              InvalidSessionField,
              7,
              "ResendRequest BeginSeqNo must be positive",
            ),
          )
      }
      let end_seq = match session_int(input, 16) {
        Some(value) => value
        None =>
          return Err(
            session_error(
              MissingSessionField,
              16,
              "ResendRequest EndSeqNo is required",
            ),
          )
      }
      if end_seq != 0 && end_seq < begin_seq {
        return Err(
          session_error(
            InvalidSessionField,
            16,
            "EndSeqNo must be zero or at least BeginSeqNo",
          ),
        )
      }
      let next = with_sequences(
        state,
        next_inbound,
        state.next_outbound_seq,
        state.status,
        state.heartbeat_seconds,
        state.pending_test_request,
      )
      Ok(session_transition(next, true, [ResendRequested(begin_seq, end_seq)]))
    }
    "4" => {
      let new_seq = match session_int(input, 36) {
        Some(value) if value > state.next_inbound_seq => value
        _ =>
          return Err(
            session_error(
              InvalidReset,
              36,
              "GapFill NewSeqNo must exceed the next expected sequence",
            ),
          )
      }
      let next = with_sequences(
        state,
        new_seq,
        state.next_outbound_seq,
        state.status,
        state.heartbeat_seconds,
        state.pending_test_request,
      )
      Ok(session_transition(next, true, [SequenceAdvanced(new_seq)]))
    }
    "5" => {
      let base = with_sequences(
        state,
        next_inbound,
        state.next_outbound_seq,
        Terminated,
        state.heartbeat_seconds,
        None,
      )
      let response_needed = state.status is Active
      if response_needed {
        let (reply, next_outbound) = make_send_action(base, "5", [])
        let next = with_sequences(
          base,
          next_inbound,
          next_outbound,
          Terminated,
          base.heartbeat_seconds,
          None,
        )
        Ok(session_transition(next, true, [PeerLoggedOut, reply]))
      } else {
        Ok(session_transition(base, true, [PeerLoggedOut]))
      }
    }
    "3" => {
      let referenced = session_int(input, 45)
      let next = with_sequences(
        state,
        next_inbound,
        state.next_outbound_seq,
        state.status,
        state.heartbeat_seconds,
        state.pending_test_request,
      )
      Ok(session_transition(next, true, [PeerRejected(referenced)]))
    }
    _ => {
      let next = with_sequences(
        state,
        next_inbound,
        state.next_outbound_seq,
        state.status,
        state.heartbeat_seconds,
        state.pending_test_request,
      )
      Ok(session_transition(next, true, [DeliverApplication(input)]))
    }
  }
}
