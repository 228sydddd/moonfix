///|
fn group_has_tag(definition : GroupDefinition, tag : Int) -> Bool {
  for member_tag in definition.member_tags {
    if member_tag == tag {
      return true
    }
  }
  false
}

///|
fn group_count_index(message : Message, tag : Int) -> Int? {
  for index, field in message.fields {
    if field.tag == tag {
      return Some(index)
    }
  }
  None
}

///|
/// Parse a flat FIX repeating group while preserving every field's wire order.
/// The parser consumes only fields named by the group definition.
pub fn parse_group(
  message : Message,
  definition : GroupDefinition,
) -> Result[GroupParse, CodecError] {
  if definition.max_entries <= 0 ||
    definition.member_tags.length() == 0 ||
    !group_has_tag(definition, definition.delimiter_tag) {
    return Err(
      codec_error(InvalidGroupCount, 0, "invalid repeating-group definition"),
    )
  }
  let count_index = match group_count_index(message, definition.count_tag) {
    Some(index) => index
    None =>
      return Err(
        codec_error(InvalidGroupCount, 0, "group count field is missing"),
      )
  }
  let count = match
    parse_decimal(message.fields[count_index].value, count_index) {
    Ok(value) => value
    Err(_) =>
      return Err(
        codec_error(
          InvalidGroupCount,
          count_index,
          "group count must be a nonnegative integer",
        ),
      )
  }
  if count > definition.max_entries {
    return Err(
      codec_error(
        GroupLimit,
        count_index,
        "group entry count exceeds configured limit",
      ),
    )
  }
  let entries : Array[GroupEntry] = []
  let mut cursor = count_index + 1
  let mut entry_index = 0
  while entry_index < count {
    if cursor >= message.fields.length() ||
      message.fields[cursor].tag != definition.delimiter_tag {
      return Err(
        codec_error(
          GroupDelimiterMissing,
          cursor,
          "each group entry must start with its delimiter",
        ),
      )
    }
    let first_index = cursor
    let entry_fields : Array[Field] = []
    let mut last_member_order = -1
    while cursor < message.fields.length() &&
          group_has_tag(definition, message.fields[cursor].tag) {
      let field = message.fields[cursor]
      if field.tag == definition.delimiter_tag && cursor != first_index {
        break
      }
      let mut member_order = -1
      for order, tag in definition.member_tags {
        if tag == field.tag {
          member_order = order
        }
      }
      if member_order < last_member_order {
        return Err(
          codec_error(
            GroupFieldUnexpected,
            cursor,
            "group fields violate dictionary order",
          ),
        )
      }
      entry_fields.push(field)
      last_member_order = member_order
      cursor += 1
    }
    entries.push({ fields: entry_fields, first_field_index: first_index, })
    entry_index += 1
  }
  Ok({ count_tag_index: count_index, entries, next_field_index: cursor, })
}

///|
test "repeating group parses entries and preserves member order" {
  let msg = message("FIX.4.4", [
    { tag: 35, value: "D", },
    { tag: 453, value: "2", },
    { tag: 448, value: "A", },
    { tag: 447, value: "D", },
    { tag: 448, value: "B", },
    { tag: 447, value: "D", },
    { tag: 11, value: "id", },
  ])
  let shape : GroupDefinition = {
    count_tag: 453,
    delimiter_tag: 448,
    member_tags: [448, 447],
    max_entries: 16,
  }
  let parsed = match parse_group(msg, shape) {
    Ok(value) => value
    Err(error) => fail(error.detail)
  }
  assert_eq(parsed.entries.length(), 2)
  assert_eq(parsed.entries[0].fields.length(), 2)
  assert_eq(parsed.entries[1].fields[0].value, "B")
  assert_eq(parsed.next_field_index, 6)
}

///|
test "repeating group rejects missing delimiter and oversized count" {
  let shape : GroupDefinition = {
    count_tag: 453,
    delimiter_tag: 448,
    member_tags: [448, 447],
    max_entries: 1,
  }
  let missing = message("FIX.4.4", [
    { tag: 453, value: "1", },
    { tag: 447, value: "D", },
  ])
  match parse_group(missing, shape) {
    Ok(_) => fail("entry delimiter must be present")
    Err(error) => assert_true(error.kind is GroupDelimiterMissing)
  }
  let oversized = message("FIX.4.4", [{ tag: 453, value: "2", }])
  match parse_group(oversized, shape) {
    Ok(_) => fail("configured group bound must be enforced")
    Err(error) => assert_true(error.kind is GroupLimit)
  }
}
