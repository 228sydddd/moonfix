///|
fn order_dictionary() -> @moonfix.Dictionary {
  {
    version: "test-1",
    fields: [
      {
        tag: 35,
        name: "MsgType",
        kind: @moonfix.TextValue,
        required: true,
        repeatable: false,
        allow_empty: false,
        allowed_values: ["D"],
        length_tag: None,
      },
      {
        tag: 11,
        name: "ClOrdID",
        kind: @moonfix.TextValue,
        required: true,
        repeatable: false,
        allow_empty: false,
        allowed_values: [],
        length_tag: None,
      },
      {
        tag: 38,
        name: "OrderQty",
        kind: @moonfix.DecimalValue,
        required: true,
        repeatable: false,
        allow_empty: false,
        allowed_values: [],
        length_tag: None,
      },
      {
        tag: 54,
        name: "Side",
        kind: @moonfix.CharacterValue,
        required: true,
        repeatable: false,
        allow_empty: false,
        allowed_values: ["1", "2"],
        length_tag: None,
      },
      {
        tag: 95,
        name: "RawDataLength",
        kind: @moonfix.IntegerValue,
        required: false,
        repeatable: false,
        allow_empty: false,
        allowed_values: [],
        length_tag: None,
      },
      {
        tag: 96,
        name: "RawData",
        kind: @moonfix.TextValue,
        required: false,
        repeatable: false,
        allow_empty: true,
        allowed_values: [],
        length_tag: Some(95),
      },
    ],
    messages: [
      {
        msg_type: "D",
        name: "NewOrderSingle",
        required_tags: [35, 11, 38, 54],
        allowed_tags: [35, 11, 38, 54, 95, 96],
        groups: [],
      },
    ],
  }
}

///|
fn order_dictionary_with_groups(
  groups : Array[@moonfix.GroupDefinition],
) -> @moonfix.Dictionary {
  let base = order_dictionary()
  {
    version: base.version,
    fields: base.fields,
    messages: [
      {
        msg_type: "D",
        name: "NewOrderSingle",
        required_tags: [35, 11, 38, 54],
        allowed_tags: [35, 11, 38, 54, 95, 96],
        groups,
      },
    ],
  }
}

///|
test "dictionary validation accepts valid fields and length pairs" {
  let msg = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "D", },
    { tag: 11, value: "client-17", },
    { tag: 38, value: "12.5", },
    { tag: 54, value: "1", },
    { tag: 95, value: "3", },
    { tag: 96, value: "abc", },
  ])
  let report = @moonfix.validate_message(order_dictionary(), msg)
  assert_true(report.valid)
  assert_eq(report.checked_fields, 6)
  assert_eq(report.message_type, "D")
}

///|
test "dictionary validation reports missing required, enum and type errors" {
  let msg = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "D", },
    { tag: 38, value: "twelve", },
    { tag: 54, value: "9", },
  ])
  let report = @moonfix.validate_message(order_dictionary(), msg)
  assert_true(!report.valid)
  let mut type_error = false
  let mut enum_error = false
  let mut required_error = false
  for issue in report.issues {
    if issue.code is @moonfix.InvalidValue && issue.tag == 38 {
      type_error = true
    }
    if issue.code is @moonfix.InvalidEnum && issue.tag == 54 {
      enum_error = true
    }
    if issue.code is @moonfix.MissingRequiredField && issue.tag == 11 {
      required_error = true
    }
  }
  assert_true(type_error)
  assert_true(enum_error)
  assert_true(required_error)
}

///|
test "dictionary validation catches duplicate singleton and unknown tags" {
  let msg = @moonfix.message("FIX.4.4", [
    { tag: 35, value: "D", },
    { tag: 11, value: "one", },
    { tag: 11, value: "two", },
    { tag: 38, value: "1", },
    { tag: 54, value: "1", },
    { tag: 9999, value: "x", },
  ])
  let report = @moonfix.validate_message(order_dictionary(), msg)
  let mut duplicate = false
  let mut unknown = false
  for issue in report.issues {
    if issue.code is @moonfix.DuplicateField &&
      issue.tag == 11 &&
      issue.field_index == 2 {
      duplicate = true
    }
    if issue.code is @moonfix.UnknownTag && issue.tag == 9999 {
      unknown = true
    }
  }
  assert_true(duplicate)
  assert_true(unknown)
}

///|
test "dictionary validator rejects unresolved references" {
  let broken : @moonfix.Dictionary = {
    version: "broken",
    fields: [
      {
        tag: 35,
        name: "MsgType",
        kind: @moonfix.TextValue,
        required: false,
        repeatable: false,
        allow_empty: false,
        allowed_values: [],
        length_tag: None,
      },
    ],
    messages: [
      {
        msg_type: "Z",
        name: "Broken",
        required_tags: [999],
        allowed_tags: [35],
        groups: [],
      },
    ],
  }
  let issues = @moonfix.validate_dictionary(broken)
  assert_true(issues.length() > 0)
  assert_true(issues[0].code is @moonfix.InvalidDictionary)
}

///|
test "dictionary rejects repeating groups with ambiguous tag ownership" {
  let first : @moonfix.GroupDefinition = {
    count_tag: 95,
    delimiter_tag: 96,
    member_tags: [96],
    max_entries: 8,
  }
  let duplicate_count : @moonfix.GroupDefinition = {
    count_tag: 95,
    delimiter_tag: 96,
    member_tags: [96],
    max_entries: 4,
  }
  let duplicate_count_issues = @moonfix.validate_dictionary(
    order_dictionary_with_groups([first, duplicate_count]),
  )
  assert_true(
    duplicate_count_issues.any(i => {
      i.code is @moonfix.InvalidDictionary && i.tag == 95
    }),
  )

  let overlapping_member : @moonfix.GroupDefinition = {
    count_tag: 11,
    delimiter_tag: 96,
    member_tags: [96],
    max_entries: 4,
  }
  let overlap_issues = @moonfix.validate_dictionary(
    order_dictionary_with_groups([first, overlapping_member]),
  )
  assert_true(
    overlap_issues.any(i => i.code is @moonfix.InvalidDictionary && i.tag == 96),
  )
}
