///|
fn validation_issue(
  code : ValidationCode,
  tag : Int,
  index : Int,
  detail : String,
) -> ValidationIssue {
  { code, tag, field_index: index, detail, }
}

///|
fn find_field_definition(
  dictionary : Dictionary,
  tag : Int,
) -> FieldDefinition? {
  for definition in dictionary.fields {
    if definition.tag == tag {
      return Some(definition)
    }
  }
  None
}

///|
fn find_message_definition(
  dictionary : Dictionary,
  msg_type : String,
) -> MessageDefinition? {
  for definition in dictionary.messages {
    if definition.msg_type == msg_type {
      return Some(definition)
    }
  }
  None
}

///|
fn contains_int(values : Array[Int], expected : Int) -> Bool {
  for value in values {
    if value == expected {
      return true
    }
  }
  false
}

///|
fn contains_string(values : Array[String], expected : String) -> Bool {
  for value in values {
    if value == expected {
      return true
    }
  }
  false
}

///|
fn number_of_tag(fields : Array[Field], tag : Int) -> Int {
  let mut count = 0
  for field in fields {
    if field.tag == tag {
      count += 1
    }
  }
  count
}

///|
fn field_value(message : Message, tag : Int) -> String? {
  for field in message.fields {
    if field.tag == tag {
      return Some(field.value)
    }
  }
  None
}

///|
/// Check the dictionary's internal references and uniqueness constraints.
pub fn validate_dictionary(dictionary : Dictionary) -> Array[ValidationIssue] {
  let issues : Array[ValidationIssue] = []
  if dictionary.version.length() == 0 {
    issues.push(
      validation_issue(
        InvalidDictionary,
        0,
        -1,
        "dictionary version cannot be empty",
      ),
    )
  }
  for i, field in dictionary.fields {
    if field.tag <= 0 || field.name.length() == 0 {
      issues.push(
        validation_issue(
          InvalidDictionary,
          field.tag,
          -1,
          "field definitions need a positive tag and a name",
        ),
      )
    }
    if field.length_tag is Some(length_tag) && length_tag <= 0 {
      issues.push(
        validation_issue(
          InvalidDictionary,
          field.tag,
          -1,
          "length tag must be positive",
        ),
      )
    }
    match field.length_tag {
      None => ()
      Some(length_tag) => {
        if length_tag == field.tag {
          issues.push(
            validation_issue(
              InvalidDictionary,
              field.tag,
              -1,
              "a data field cannot use itself as its length tag",
            ),
          )
        }
        match find_field_definition(dictionary, length_tag) {
          Some(length_field) if length_field.kind is IntegerValue =>
            if length_field.repeatable || length_field.length_tag is Some(_) {
              issues.push(
                validation_issue(
                  InvalidDictionary,
                  length_tag,
                  -1,
                  "a length tag must be a nonrepeatable integer field",
                ),
              )
            }
          Some(_) =>
            issues.push(
              validation_issue(
                InvalidDictionary,
                length_tag,
                -1,
                "a length tag must have an integer field definition",
              ),
            )
          None =>
            issues.push(
              validation_issue(
                InvalidDictionary,
                length_tag,
                -1,
                "a length tag must have a field definition",
              ),
            )
        }
        for j in (i + 1)..<dictionary.fields.length() {
          if dictionary.fields[j].length_tag == Some(length_tag) {
            issues.push(
              validation_issue(
                InvalidDictionary,
                length_tag,
                -1,
                "a length tag cannot be shared by multiple data fields",
              ),
            )
          }
        }
      }
    }
    for j in (i + 1)..<dictionary.fields.length() {
      if dictionary.fields[j].tag == field.tag {
        issues.push(
          validation_issue(
            InvalidDictionary,
            field.tag,
            -1,
            "field tags must be unique",
          ),
        )
      }
    }
    for j, value in field.allowed_values {
      for k in (j + 1)..<field.allowed_values.length() {
        if field.allowed_values[k] == value {
          issues.push(
            validation_issue(
              InvalidDictionary,
              field.tag,
              -1,
              "enum values must be unique",
            ),
          )
        }
      }
    }
  }
  for i, definition in dictionary.messages {
    if definition.msg_type.length() == 0 || definition.name.length() == 0 {
      issues.push(
        validation_issue(
          InvalidDictionary,
          35,
          -1,
          "message definitions need a MsgType and a name",
        ),
      )
    }
    for j in (i + 1)..<dictionary.messages.length() {
      if dictionary.messages[j].msg_type == definition.msg_type {
        issues.push(
          validation_issue(
            InvalidDictionary,
            35,
            -1,
            "message types must be unique",
          ),
        )
      }
    }
    for tag in definition.required_tags {
      if !contains_int(definition.allowed_tags, tag) {
        issues.push(
          validation_issue(
            InvalidDictionary,
            tag,
            -1,
            "required tags must also be allowed",
          ),
        )
      }
      if find_field_definition(dictionary, tag) is None {
        issues.push(
          validation_issue(
            InvalidDictionary,
            tag,
            -1,
            "required tag has no field definition",
          ),
        )
      }
    }
    for tag in definition.allowed_tags {
      if find_field_definition(dictionary, tag) is None {
        issues.push(
          validation_issue(
            InvalidDictionary,
            tag,
            -1,
            "allowed tag has no field definition",
          ),
        )
      }
    }
    for i, group in definition.groups {
      if group.count_tag <= 0 ||
        group.delimiter_tag <= 0 ||
        group.max_entries <= 0 ||
        group.member_tags.length() == 0 {
        issues.push(
          validation_issue(
            InvalidDictionary,
            group.count_tag,
            -1,
            "group requires positive tags, members, and a limit",
          ),
        )
      }
      if !contains_int(group.member_tags, group.delimiter_tag) {
        issues.push(
          validation_issue(
            InvalidDictionary,
            group.delimiter_tag,
            -1,
            "group delimiter must be listed as a member",
          ),
        )
      }
      if group_has_tag(group, group.count_tag) {
        issues.push(
          validation_issue(
            InvalidDictionary,
            group.count_tag,
            -1,
            "group count tag must not also be a member",
          ),
        )
      }
      if !contains_int(definition.allowed_tags, group.count_tag) {
        issues.push(
          validation_issue(
            InvalidDictionary,
            group.count_tag,
            -1,
            "group count tag must be allowed by its message",
          ),
        )
      }
      match find_field_definition(dictionary, group.count_tag) {
        Some(field) if field.kind is IntegerValue => ()
        Some(_) | None =>
          issues.push(
            validation_issue(
              InvalidDictionary,
              group.count_tag,
              -1,
              "group count tag must have an integer field definition",
            ),
          )
      }
      for tag in group.member_tags {
        if !contains_int(definition.allowed_tags, tag) ||
          find_field_definition(dictionary, tag) is None {
          issues.push(
            validation_issue(
              InvalidDictionary,
              tag,
              -1,
              "group members must be defined and message-allowed",
            ),
          )
        }
      }
      for i, tag in group.member_tags {
        for j in (i + 1)..<group.member_tags.length() {
          if group.member_tags[j] == tag {
            issues.push(
              validation_issue(
                InvalidDictionary,
                tag,
                -1,
                "group member tags must be unique",
              ),
            )
          }
        }
      }
      for j in (i + 1)..<definition.groups.length() {
        let other = definition.groups[j]
        if other.count_tag == group.count_tag {
          issues.push(
            validation_issue(
              InvalidDictionary,
              group.count_tag,
              -1,
              "group count tags must be unique within a message",
            ),
          )
        }
        if group_has_tag(group, other.count_tag) ||
          group_has_tag(other, group.count_tag) {
          issues.push(
            validation_issue(
              InvalidDictionary,
              other.count_tag,
              -1,
              "group count tags must not overlap another group's members",
            ),
          )
        }
        for tag in group.member_tags {
          if group_has_tag(other, tag) {
            issues.push(
              validation_issue(
                InvalidDictionary,
                tag,
                -1,
                "group member tags must not overlap within a message",
              ),
            )
          }
        }
      }
    }
  }
  issues
}

///|
fn all_digits(value : String, start : Int, end : Int) -> Bool {
  if start < 0 || end > value.length() || start >= end {
    return false
  }
  for i in start..<end {
    let digit = value.code_unit_at(i).to_int() - 48
    if digit < 0 || digit > 9 {
      return false
    }
  }
  true
}

///|
fn is_integer(value : String) -> Bool {
  if value.length() == 0 {
    return false
  }
  let start = if value[0] == '-' || value[0] == '+' { 1 } else { 0 }
  all_digits(value, start, value.length())
}

///|
fn is_decimal(value : String) -> Bool {
  if value.length() == 0 {
    return false
  }
  let start = if value[0] == '-' || value[0] == '+' { 1 } else { 0 }
  if start >= value.length() {
    return false
  }
  let mut dot = -1
  for i in start..<value.length() {
    if value[i] == '.' {
      if dot >= 0 {
        return false
      }
      dot = i
    } else {
      let digit = value.code_unit_at(i).to_int() - 48
      if digit < 0 || digit > 9 {
        return false
      }
    }
  }
  dot != start && dot != value.length() - 1
}

///|
fn integer_slice(value : String, start : Int, end : Int) -> Int {
  let mut number = 0
  for i in start..<end {
    number = number * 10 + value.code_unit_at(i).to_int() - 48
  }
  number
}

///|
fn is_leap_year(year : Int) -> Bool {
  year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

///|
/// Validate FIX UTCTimestamp lexical form YYYYMMDD-HH:MM:SS[.sss...].
fn is_utc_timestamp(value : String) -> Bool {
  if value.length() < 17 || value.length() > 24 {
    return false
  }
  if value[8] != '-' || value[11] != ':' || value[14] != ':' {
    return false
  }
  if !all_digits(value, 0, 8) ||
    !all_digits(value, 9, 11) ||
    !all_digits(value, 12, 14) ||
    !all_digits(value, 15, 17) {
    return false
  }
  let year = integer_slice(value, 0, 4)
  let month = integer_slice(value, 4, 6)
  let day = integer_slice(value, 6, 8)
  let hour = integer_slice(value, 9, 11)
  let minute = integer_slice(value, 12, 14)
  let second = integer_slice(value, 15, 17)
  if year == 0 ||
    month < 1 ||
    month > 12 ||
    hour > 23 ||
    minute > 59 ||
    second > 60 {
    return false
  }
  let days = if month == 2 {
    if is_leap_year(year) {
      29
    } else {
      28
    }
  } else if month == 4 || month == 6 || month == 9 || month == 11 {
    30
  } else {
    31
  }
  if day < 1 || day > days {
    return false
  }
  if value.length() == 17 {
    return true
  }
  value[17] == '.' && all_digits(value, 18, value.length())
}

///|
fn value_matches(kind : ValueKind, value : String) -> Bool {
  match kind {
    TextValue => true
    IntegerValue => is_integer(value)
    DecimalValue => is_decimal(value)
    BooleanValue => value == "Y" || value == "N"
    CharacterValue => value.length() == 1
    UtcTimestampValue => is_utc_timestamp(value)
  }
}

///|
fn parse_length(value : String) -> Int? {
  if !all_digits(value, 0, value.length()) {
    return None
  }
  let mut number = 0
  for i in 0..<value.length() {
    let digit = value.code_unit_at(i).to_int() - 48
    if number > 2_000_000 {
      return None
    }
    number = number * 10 + digit
  }
  Some(number)
}

///|
/// Validate a decoded message with a caller-owned dictionary and stable issue codes.
pub fn validate_message(
  dictionary : Dictionary,
  message : Message,
) -> ValidationReport {
  let issues = validate_dictionary(dictionary)
  let mut msg_type = ""
  let mut msg_type_count = 0
  for i, field in message.fields {
    if field.tag == 35 {
      if msg_type_count == 0 {
        msg_type = field.value
      }
      msg_type_count += 1
      if msg_type_count > 1 {
        issues.push(
          validation_issue(DuplicateField, 35, i, "MsgType must appear once"),
        )
      }
    }
  }
  if msg_type_count == 0 {
    issues.push(
      validation_issue(MissingMsgType, 35, -1, "message has no MsgType (35)"),
    )
  }
  let message_def = find_message_definition(dictionary, msg_type)
  if msg_type_count > 0 && message_def is None {
    issues.push(
      validation_issue(
        UnknownMessageType,
        35,
        -1,
        "message type is not defined",
      ),
    )
  }
  for i, field in message.fields {
    match find_field_definition(dictionary, field.tag) {
      None =>
        issues.push(
          validation_issue(UnknownTag, field.tag, i, "field tag is not defined"),
        )
      Some(field_def) => {
        if field.value.length() == 0 && !field_def.allow_empty {
          issues.push(
            validation_issue(
              EmptyValue,
              field.tag,
              i,
              "field value cannot be empty",
            ),
          )
        } else if field.value.length() > 0 &&
          !value_matches(field_def.kind, field.value) {
          issues.push(
            validation_issue(
              InvalidValue,
              field.tag,
              i,
              "value does not match its declared type",
            ),
          )
        }
        if field_def.allowed_values.length() > 0 &&
          !contains_string(field_def.allowed_values, field.value) {
          issues.push(
            validation_issue(
              InvalidEnum,
              field.tag,
              i,
              "value is outside the declared enum",
            ),
          )
        }
        if !field_def.repeatable &&
          number_of_tag(message.fields, field.tag) > 1 &&
          i > 0 {
          issues.push(
            validation_issue(
              DuplicateField,
              field.tag,
              i,
              "field is not repeatable",
            ),
          )
        }
        if field_def.length_tag is Some(length_tag) {
          match field_value(message, length_tag) {
            None =>
              issues.push(
                validation_issue(
                  InvalidLengthPair,
                  length_tag,
                  i,
                  "paired length field is missing",
                ),
              )
            Some(length_text) =>
              match parse_length(length_text) {
                None =>
                  issues.push(
                    validation_issue(
                      InvalidLengthPair,
                      length_tag,
                      i,
                      "paired length must be a nonnegative integer",
                    ),
                  )
                Some(length) =>
                  if length != field.value.length() {
                    issues.push(
                      validation_issue(
                        InvalidLengthPair,
                        field.tag,
                        i,
                        "paired length differs from value length",
                      ),
                    )
                  }
              }
          }
        }
      }
    }
    match message_def {
      Some(definition) =>
        if !contains_int(definition.allowed_tags, field.tag) {
          issues.push(
            validation_issue(
              DisallowedField,
              field.tag,
              i,
              "field is not allowed for this MsgType",
            ),
          )
        }
      None => ()
    }
  }
  match message_def {
    Some(definition) => {
      for tag in definition.required_tags {
        if number_of_tag(message.fields, tag) == 0 {
          issues.push(
            validation_issue(
              MissingRequiredField,
              tag,
              -1,
              "required message field is missing",
            ),
          )
        }
      }
      for group in definition.groups {
        match parse_group(message, group) {
          Ok(parsed) =>
            if parsed.entries.length() !=
              number_of_tag(message.fields, group.count_tag) {
              issues.push(
                validation_issue(
                  InvalidGroup,
                  group.count_tag,
                  parsed.count_tag_index,
                  "group count tag must occur once",
                ),
              )
            }
          Err(error) =>
            issues.push(
              validation_issue(
                InvalidGroup,
                group.count_tag,
                error.offset,
                error.detail,
              ),
            )
        }
      }
    }
    None => ()
  }
  {
    valid: issues.length() == 0,
    message_type: msg_type,
    checked_fields: message.fields.length(),
    issues,
  }
}
