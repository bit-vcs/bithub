///|
test "parse_int_safe parses valid integers" {
  inspect(parse_int_safe("123"), content="123")
  inspect(parse_int_safe("0"), content="0")
  inspect(parse_int_safe("999"), content="999")
  inspect(parse_int_safe("1"), content="1")
}

///|
test "parse_int_safe ignores non-digit characters" {
  inspect(parse_int_safe("abc"), content="0")
  inspect(parse_int_safe("12a34"), content="1234")
  inspect(parse_int_safe("a123b"), content="123")
  inspect(parse_int_safe("!@#$%"), content="0")
}

///|
test "parse_int_safe handles mixed content" {
  inspect(parse_int_safe("id123"), content="123")
  inspect(parse_int_safe("123px"), content="123")
  inspect(parse_int_safe("v1.2.3"), content="123")
  inspect(parse_int_safe("user-456"), content="456")
}

///|
test "parse_int_safe handles empty and whitespace" {
  inspect(parse_int_safe(""), content="0")
  inspect(parse_int_safe(" "), content="0")
  inspect(parse_int_safe("   "), content="0")
  inspect(parse_int_safe("\t\n"), content="0")
}

///|
test "parse_int_safe handles leading/trailing non-digits" {
  inspect(parse_int_safe("abc123"), content="123")
  inspect(parse_int_safe("123def"), content="123")
  inspect(parse_int_safe("abc123def"), content="123")
  inspect(parse_int_safe("---789+++"), content="789")
}

///|
test "parse_int_safe handles large numbers" {
  inspect(parse_int_safe("1000000"), content="1000000")
  inspect(parse_int_safe("999999999"), content="999999999")
  inspect(parse_int_safe("a1b2c3d4e5f6g7h8i9j0"), content="1234567890")
}