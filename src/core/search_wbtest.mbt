///|
// Whitebox tests for string_contains function
// These tests can access private functions in api_state.mbt

///|
test "string_contains: empty needle matches any string" {
  inspect(string_contains("hello", ""), content="true")
  inspect(string_contains("", ""), content="true")
  inspect(string_contains("world", ""), content="true")
}

///|
test "string_contains: exact match" {
  inspect(string_contains("hello", "hello"), content="true")
  inspect(string_contains("test", "test"), content="true")
  inspect(string_contains("a", "a"), content="true")
}

///|
test "string_contains: substring at start" {
  inspect(string_contains("hello world", "hello"), content="true")
  inspect(string_contains("testing", "test"), content="true")
  inspect(string_contains("abc", "a"), content="true")
}

///|
test "string_contains: substring at middle" {
  inspect(string_contains("hello world", "lo wo"), content="true")
  inspect(string_contains("testing", "est"), content="true")
  inspect(string_contains("abcdef", "cd"), content="true")
}

///|
test "string_contains: substring at end" {
  inspect(string_contains("hello world", "world"), content="true")
  inspect(string_contains("testing", "ing"), content="true")
  inspect(string_contains("abc", "c"), content="true")
}

///|
test "string_contains: no match" {
  inspect(string_contains("hello", "xyz"), content="false")
  inspect(string_contains("test", "missing"), content="false")
  inspect(string_contains("abc", "def"), content="false")
}

///|
test "string_contains: case sensitivity" {
  inspect(string_contains("Hello", "hello"), content="false")
  inspect(string_contains("TEST", "test"), content="false")
  inspect(string_contains("World", "WORLD"), content="false")
  inspect(string_contains("CamelCase", "camelcase"), content="false")
}

///|
test "string_contains: needle longer than haystack" {
  inspect(string_contains("hi", "hello"), content="false")
  inspect(string_contains("a", "abc"), content="false")
  inspect(string_contains("", "x"), content="false")
  inspect(string_contains("short", "much longer string"), content="false")
}