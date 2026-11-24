///|
fn capture_test_message(
  seq : Int,
  extra? : Array[@moonfix.Field] = [],
  sender? : String = "BUY",
) -> String {
  let fields = [
    @moonfix.Field::{ tag: 35, value: "0", },
    @moonfix.Field::{ tag: 49, value: sender, },
    @moonfix.Field::{ tag: 56, value: "SELL", },
    @moonfix.Field::{ tag: 34, value: seq.to_string(), },
    ..extra,
  ]
  match @moonfix.encode_message(@moonfix.message("FIX.4.4", fields)) {
    Ok(wire) => wire
    Err(_) => ""
  }
}

///|
test "capture accepts concatenated frames and CRLF separators" {
  let wire = capture_test_message(1) + "\r\n" + capture_test_message(2)
  let audit = @moonfix.audit_capture(wire)
  assert_eq(audit.records.length(), 2)
  assert_eq(audit.findings.length(), 0)
  assert_eq(audit.records[0].byte_offset, 0)
  assert_eq(audit.records[1].message_index, 1)
}

///|
test "capture distinguishes gaps duplicate retransmits and ordinary reordering" {
  let wire = capture_test_message(2) +
    capture_test_message(4) +
    capture_test_message(4, extra=[@moonfix.Field::{ tag: 43, value: "Y", }]) +
    capture_test_message(3)
  let audit = @moonfix.audit_capture(wire)
  assert_eq(audit.findings.length(), 3)
  assert_true(audit.findings[0].code is @moonfix.CaptureSequenceGap)
  assert_eq(audit.findings[0].expected_sequence, Some(3))
  assert_true(audit.findings[1].code is @moonfix.CaptureDuplicateSequence)
  assert_true(audit.findings[2].code is @moonfix.CaptureOutOfOrderSequence)
}

///|
test "capture reports malformed frame and resynchronizes at next message" {
  let valid = capture_test_message(1)
  let corrupt = valid[0:valid.length() - 3].to_owned() + "999\u{1}"
  let audit = @moonfix.audit_capture(corrupt + valid)
  assert_eq(audit.records.length(), 1)
  assert_true(audit.findings.any(f => f.code is @moonfix.CaptureFramingError))
  assert_eq(audit.records[0].byte_offset, corrupt.length())
}

///|
test "capture reports non-separator bytes between messages" {
  let wire = capture_test_message(1) + "noise" + capture_test_message(2)
  let audit = @moonfix.audit_capture(wire)
  assert_eq(audit.records.length(), 2)
  assert_true(audit.findings.any(f => f.code is @moonfix.CaptureFramingError))
}

///|
test "capture reports missing sequence and CompIDs" {
  let wire = match
    @moonfix.encode_message(
      @moonfix.message("FIX.4.4", [@moonfix.Field::{ tag: 35, value: "0", }]),
    ) {
    Ok(value) => value
    Err(_) => ""
  }
  let audit = @moonfix.audit_capture(wire)
  assert_true(
    audit.findings.any(f => f.code is @moonfix.CaptureMissingSequence),
  )
  assert_true(audit.findings.any(f => f.code is @moonfix.CaptureMissingCompId))
}

///|
test "capture JSONL escapes user controlled identifiers" {
  let wire = capture_test_message(1, sender="BUY\"\\DESK")
  let audit = @moonfix.audit_capture(wire)
  let json = @moonfix.capture_audit_jsonl(audit)
  assert_true(json.contains("BUY\\\"\\\\DESK"))
  assert_true(json.has_suffix("\n"))
}
