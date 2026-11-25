///|
/// A raw FIX field; order and duplicate tags are intentionally preserved.
pub(all) struct Field {
  tag : Int32
  value : String
}

///|
/// A decoded message without the three framing fields.
pub(all) struct Message {
  begin_string : String
  fields : Array[Field]
}

///|
/// Stable classifications for wire and framing failures.
pub(all) enum CodecErrorKind {
  NonAscii
  InvalidField
  InvalidTag
  InvalidBodyLength
  BodyLengthMismatch
  InvalidChecksum
  ChecksumMismatch
  FramingLimit
  ReservedTag
  InvalidGroupCount
  GroupDelimiterMissing
  GroupFieldUnexpected
  GroupLimit
}

///|
pub(all) struct CodecError {
  kind : CodecErrorKind
  offset : Int32
  detail : String
}

///|
pub(all) struct ParseLimits {
  max_message_bytes : Int32
  max_fields : Int32
}

///|
pub fn default_parse_limits() -> ParseLimits {
  { max_message_bytes: 1_048_576, max_fields: 16_384, }
}

///|
fn codec_error(
  kind : CodecErrorKind,
  offset : Int32,
  detail : String,
) -> CodecError {
  { kind, offset, detail, }
}

///|
pub fn message(begin_string : String, fields : Array[Field]) -> Message {
  { begin_string, fields, }
}

///|
/// Lexical value constraint supplied by the application dictionary.
pub(all) enum ValueKind {
  TextValue
  IntegerValue
  DecimalValue
  BooleanValue
  CharacterValue
  UtcTimestampValue
}

///|
/// Validation metadata for one tag; `allowed_values` is an optional enum set.
pub(all) struct FieldDefinition {
  tag : Int32
  name : String
  kind : ValueKind
  required : Bool
  repeatable : Bool
  allow_empty : Bool
  allowed_values : Array[String]
  length_tag : Int32?
}

///|
/// One repeating-group shape. Members are checked in their supplied wire order.
pub(all) struct GroupDefinition {
  count_tag : Int32
  delimiter_tag : Int32
  member_tags : Array[Int32]
  max_entries : Int32
}

///|
/// Message-level required and allowed body tags for one MsgType value.
pub(all) struct MessageDefinition {
  msg_type : String
  name : String
  required_tags : Array[Int32]
  allowed_tags : Array[Int32]
  groups : Array[GroupDefinition]
}

///|
/// A caller-owned dictionary; MoonFIX does not bundle a licensed venue dictionary.
pub(all) struct Dictionary {
  version : String
  fields : Array[FieldDefinition]
  messages : Array[MessageDefinition]
}

///|
/// Stable validation categories for machine-readable diagnostics.
pub(all) enum ValidationCode {
  MissingMsgType
  UnknownMessageType
  UnknownTag
  DuplicateField
  MissingRequiredField
  DisallowedField
  EmptyValue
  InvalidValue
  InvalidEnum
  InvalidLengthPair
  InvalidDictionary
  InvalidGroup
}

///|
/// One validation finding. `field_index` is -1 for message-level findings.
pub(all) struct ValidationIssue {
  code : ValidationCode
  tag : Int32
  field_index : Int32
  detail : String
}

///|
/// Full validation output; valid is true only when no issues were collected.
pub(all) struct ValidationReport {
  valid : Bool
  message_type : String
  checked_fields : Int32
  issues : Array[ValidationIssue]
}

///|
/// One parsed occurrence in a repeating group.
pub(all) struct GroupEntry {
  fields : Array[Field]
  first_field_index : Int32
}

///|
/// Parsed group entries and the field index immediately after the group region.
pub(all) struct GroupParse {
  count_tag_index : Int32
  entries : Array[GroupEntry]
  next_field_index : Int32
}
