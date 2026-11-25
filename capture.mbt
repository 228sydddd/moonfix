///|
/// Sequence findings are scoped to a FIX CompID pair, not to a whole file.
pub(all) enum CaptureFindingCode {
  CaptureFramingError
  CaptureSequenceGap
  CaptureDuplicateSequence
  CaptureOutOfOrderSequence
  CaptureMissingSequence
  CaptureMissingCompId
}

///|
/// One stable, position-aware finding produced while reading an offline capture.
pub(all) struct CaptureFinding {
  code : CaptureFindingCode
  byte_offset : Int32
  message_index : Int32
  expected_sequence : Int32?
  actual_sequence : Int32?
  sender : String
  target : String
  detail : String
}

///|
/// Metadata retained for a successfully framed capture message.
pub(all) struct CaptureRecord {
  byte_offset : Int32
  wire_length : Int32
  message_index : Int32
  begin_string : String
  message_type : String
  sequence_number : Int32?
  possible_duplicate : Bool
  reset_sequence_numbers : Bool
  sender : String
  target : String
}

///|
/// A deterministic offline capture audit. Records and findings follow wire order.
pub(all) struct CaptureAudit {
  records : Array[CaptureRecord]
  findings : Array[CaptureFinding]
  bytes_consumed : Int32
  trailing_bytes : Int32
}

///|
priv struct CaptureSequenceState {
  begin_string : String
  sender : String
  target : String
  next_expected : Int32?
}

///|
fn capture_field(message : Message, tag : Int32) -> String? {
  for field in message.fields {
    if field.tag == tag {
      return Some(field.value)
    }
  }
  None
}

///|
fn capture_unique_field(message : Message, tag : Int32) -> String? {
  let mut value : String? = None
  for field in message.fields {
    if field.tag == tag {
      if value is Some(_) {
        return None
      }
      value = Some(field.value)
    }
  }
  value
}

///|
fn capture_integer(message : Message, tag : Int32) -> Int32? {
  match capture_field(message, tag) {
    None => None
    Some(value) =>
      match parse_decimal(value, 0) {
        Ok(number) => Some(number)
        Err(_) => None
      }
  }
}

///|
fn capture_finding(
  code : CaptureFindingCode,
  byte_offset : Int32,
  message_index : Int32,
  expected_sequence : Int32?,
  actual_sequence : Int32?,
  sender : String,
  target : String,
  detail : String,
) -> CaptureFinding {
  {
    code,
    byte_offset,
    message_index,
    expected_sequence,
    actual_sequence,
    sender,
    target,
    detail,
  }
}

///|
fn capture_record(
  offset : Int32,
  length : Int32,
  index : Int32,
  message : Message,
) -> CaptureRecord {
  {
    byte_offset: offset,
    wire_length: length,
    message_index: index,
    begin_string: message.begin_string,
    message_type: capture_field(message, 35).unwrap_or(""),
    sequence_number: capture_integer(message, 34),
    possible_duplicate: capture_field(message, 43) == Some("Y"),
    reset_sequence_numbers: capture_unique_field(message, 35) == Some("A") &&
    capture_unique_field(message, 141) == Some("Y") &&
    capture_unique_field(message, 34) == Some("1"),
    sender: capture_field(message, 49).unwrap_or(""),
    target: capture_field(message, 56).unwrap_or(""),
  }
}

///|
fn find_capture_start(wire : String, start : Int32) -> Int32? {
  let mut cursor = start
  while cursor + 1 < wire.length() {
    if wire[cursor] == '8' && wire[cursor + 1] == '=' {
      return Some(cursor)
    }
    cursor += 1
  }
  None
}

///|
fn find_capture_message_end(
  wire : String,
  start : Int32,
) -> Result[Int32, CodecError] {
  let first = match read_field(wire, start, wire.length()) {
    Ok(field) => field
    Err(error) => return Err(error)
  }
  if first.0.tag != 8 {
    return Err(
      codec_error(
        InvalidField,
        start,
        "capture record must begin with BeginString (8)",
      ),
    )
  }
  let second = match read_field(wire, first.1, wire.length()) {
    Ok(field) => field
    Err(error) => return Err(error)
  }
  if second.0.tag != 9 {
    return Err(
      codec_error(
        InvalidField,
        first.1,
        "BodyLength (9) must follow BeginString",
      ),
    )
  }
  let body_length = match parse_decimal(second.0.value, first.1) {
    Ok(length) => length
    Err(error) => return Err(error)
  }
  let checksum_start = second.1 + body_length
  let end = checksum_start + 7
  if body_length > 2_000_000 || end > wire.length() {
    return Err(
      codec_error(
        BodyLengthMismatch,
        second.1,
        "capture record is truncated or exceeds the framing limit",
      ),
    )
  }
  if end <= start {
    return Err(
      codec_error(
        BodyLengthMismatch,
        start,
        "capture framing arithmetic overflowed",
      ),
    )
  }
  Ok(end)
}

///|

///|
fn capture_sequence_state_index(
  states : Array[CaptureSequenceState],
  record : CaptureRecord,
) -> Int32? {
  for index, state in states {
    if state.begin_string == record.begin_string &&
      state.sender == record.sender &&
      state.target == record.target {
      return Some(index)
    }
  }
  None
}

///|
fn append_record_findings(
  sequence_states : Array[CaptureSequenceState],
  findings : Array[CaptureFinding],
  record : CaptureRecord,
) -> Unit {
  if record.sequence_number is None {
    findings.push(
      capture_finding(
        CaptureMissingSequence,
        record.byte_offset,
        record.message_index,
        None,
        None,
        record.sender,
        record.target,
        "message has no valid MsgSeqNum (34)",
      ),
    )
  }
  if record.sender.length() == 0 || record.target.length() == 0 {
    findings.push(
      capture_finding(
        CaptureMissingCompId,
        record.byte_offset,
        record.message_index,
        None,
        record.sequence_number,
        record.sender,
        record.target,
        "sequence audit requires SenderCompID (49) and TargetCompID (56)",
      ),
    )
    return
  }
  let state_index = match
    capture_sequence_state_index(sequence_states, record) {
    Some(index) => index
    None => {
      sequence_states.push({
        begin_string: record.begin_string,
        sender: record.sender,
        target: record.target,
        next_expected: None,
      })
      sequence_states.length() - 1
    }
  }
  let state = sequence_states[state_index]
  match record.sequence_number {
    None => ()
    Some(_) if record.reset_sequence_numbers =>
      sequence_states[state_index] = {
        begin_string: state.begin_string,
        sender: state.sender,
        target: state.target,
        next_expected: Some(2),
      }
    Some(actual) => {
      match state.next_expected {
        None => ()
        Some(expected) =>
          if actual > expected {
            findings.push(
              capture_finding(
                CaptureSequenceGap,
                record.byte_offset,
                record.message_index,
                Some(expected),
                Some(actual),
                record.sender,
                record.target,
                "sequence number skips one or more messages in this direction",
              ),
            )
          } else if actual < expected {
            let duplicate = record.possible_duplicate
            let code = if duplicate {
              CaptureDuplicateSequence
            } else {
              CaptureOutOfOrderSequence
            }
            let detail = if duplicate {
              "PossDupFlag (43)=Y marks a retransmitted sequence"
            } else {
              "sequence number is behind the next expected value without PossDupFlag"
            }
            findings.push(
              capture_finding(
                code,
                record.byte_offset,
                record.message_index,
                Some(expected),
                Some(actual),
                record.sender,
                record.target,
                detail,
              ),
            )
          }
      }
      if state.next_expected is None ||
        (state.next_expected is Some(value) && actual >= value) {
        sequence_states[state_index] = {
          begin_string: state.begin_string,
          sender: state.sender,
          target: state.target,
          next_expected: Some(actual + 1),
        }
      }
    }
  }
}

///|
/// Scan concatenated SOH-delimited FIX messages and audit framing and per-session sequence order.
/// Newline/CRLF separators between messages are tolerated; other garbage is reported and resynchronized.
pub fn audit_capture(
  wire : String,
  limits~ : ParseLimits = default_parse_limits(),
) -> CaptureAudit {
  let records : Array[CaptureRecord] = []
  let findings : Array[CaptureFinding] = []
  let sequence_states : Array[CaptureSequenceState] = []
  let mut cursor = 0
  let mut consumed = 0
  while cursor < wire.length() {
    match find_capture_start(wire, cursor) {
      None => {
        let trailing = wire.length() - cursor
        if trailing > 0 && !capture_only_line_endings(wire, cursor) {
          findings.push(
            capture_finding(
              CaptureFramingError,
              cursor,
              records.length(),
              None,
              None,
              "",
              "",
              "unrecognized trailing bytes do not begin a FIX message",
            ),
          )
        }
        cursor = wire.length()
      }
      Some(start) => {
        if start > cursor && !capture_only_line_endings(wire, cursor, end=start) {
          findings.push(
            capture_finding(
              CaptureFramingError,
              cursor,
              records.length(),
              None,
              None,
              "",
              "",
              "bytes between FIX messages are not CR or LF separators",
            ),
          )
        }
        match find_capture_message_end(wire, start) {
          Err(error) => {
            findings.push(
              capture_finding(
                CaptureFramingError,
                error.offset,
                records.length(),
                None,
                None,
                "",
                "",
                error.detail,
              ),
            )
            cursor = start + 2
          }
          Ok(end) => {
            let frame = wire[start:end].to_owned()
            match parse_message(frame, limits~) {
              Err(error) => {
                findings.push(
                  capture_finding(
                    CaptureFramingError,
                    start + error.offset,
                    records.length(),
                    None,
                    None,
                    "",
                    "",
                    error.detail,
                  ),
                )
                cursor = start + 2
              }
              Ok(message) => {
                let record = capture_record(
                  start,
                  end - start,
                  records.length(),
                  message,
                )
                append_record_findings(sequence_states, findings, record)
                records.push(record)
                cursor = end
                consumed = end
              }
            }
          }
        }
      }
    }
  }
  {
    records,
    findings,
    bytes_consumed: consumed,
    trailing_bytes: wire.length() - consumed,
  }
}

///|
fn capture_only_line_endings(
  wire : String,
  start : Int32,
  end~ : Int32 = wire.length(),
) -> Bool {
  let mut index = start
  while index < end {
    if wire[index] != '\n' && wire[index] != '\r' {
      return false
    }
    index += 1
  }
  true
}

///|
fn finding_code_name(code : CaptureFindingCode) -> String {
  match code {
    CaptureFramingError => "framing_error"
    CaptureSequenceGap => "sequence_gap"
    CaptureDuplicateSequence => "duplicate_sequence"
    CaptureOutOfOrderSequence => "out_of_order_sequence"
    CaptureMissingSequence => "missing_sequence"
    CaptureMissingCompId => "missing_comp_id"
  }
}

///|
fn json_string(value : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for char in value {
    match char {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ =>
        if char.to_int() < 32 {
          out.write_string("\\u00")
          out.write_string(hex_digit(char.to_int() / 16))
          out.write_string(hex_digit(char.to_int() % 16))
        } else {
          out.write_char(char)
        }
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
fn hex_digit(value : Int32) -> String {
  match value {
    0 => "0"
    1 => "1"
    2 => "2"
    3 => "3"
    4 => "4"
    5 => "5"
    6 => "6"
    7 => "7"
    8 => "8"
    9 => "9"
    10 => "a"
    11 => "b"
    12 => "c"
    13 => "d"
    14 => "e"
    _ => "f"
  }
}

///|
fn json_optional_int(value : Int32?) -> String {
  match value {
    Some(number) => number.to_string()
    None => "null"
  }
}

///|
fn json_record(record : CaptureRecord) -> String {
  "{\"type\":\"message\",\"index\":" +
  record.message_index.to_string() +
  ",\"offset\":" +
  record.byte_offset.to_string() +
  ",\"length\":" +
  record.wire_length.to_string() +
  ",\"begin_string\":" +
  json_string(record.begin_string) +
  ",\"msg_type\":" +
  json_string(record.message_type) +
  ",\"seq_num\":" +
  json_optional_int(record.sequence_number) +
  ",\"possible_duplicate\":" +
  (if record.possible_duplicate { "true" } else { "false" }) +
  ",\"reset_seq_num\":" +
  (if record.reset_sequence_numbers { "true" } else { "false" }) +
  ",\"sender\":" +
  json_string(record.sender) +
  ",\"target\":" +
  json_string(record.target) +
  "}"
}

///|
fn json_finding(finding : CaptureFinding) -> String {
  "{\"type\":\"finding\",\"code\":" +
  json_string(finding_code_name(finding.code)) +
  ",\"index\":" +
  finding.message_index.to_string() +
  ",\"offset\":" +
  finding.byte_offset.to_string() +
  ",\"expected_seq\":" +
  json_optional_int(finding.expected_sequence) +
  ",\"actual_seq\":" +
  json_optional_int(finding.actual_sequence) +
  ",\"sender\":" +
  json_string(finding.sender) +
  ",\"target\":" +
  json_string(finding.target) +
  ",\"detail\":" +
  json_string(finding.detail) +
  "}"
}

///|
/// Render machine-stable JSON Lines: message rows first in wire order, then findings in detection order.
pub fn capture_audit_jsonl(audit : CaptureAudit) -> String {
  let output = StringBuilder()
  for record in audit.records {
    output.write_string(json_record(record))
    output.write_char('\n')
  }
  for finding in audit.findings {
    output.write_string(json_finding(finding))
    output.write_char('\n')
  }
  output.to_string()
}
