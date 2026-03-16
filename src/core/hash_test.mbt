///|
test "simple_hash with empty string returns a number" {
  let result = simple_hash("")
  // Should return a valid string representation of a number
  inspect(result, content="5381")
}

///|
test "simple_hash with hello returns consistent value" {
  let result = simple_hash("hello")
  // Should return the same hash every time for "hello"
  inspect(result, content="261238937")
}

///|
test "simple_hash different inputs produce different outputs" {
  let hash_a = simple_hash("a")
  let hash_b = simple_hash("b")
  // Different inputs should produce different hashes
  assert_false(hash_a == hash_b)
}

///|
test "simple_hash same input gives same output" {
  let hash1 = simple_hash("test")
  let hash2 = simple_hash("test")
  // Same input should always produce the same hash
  assert_true(hash1 == hash2)
}

///|
test "simple_hash handles various string lengths" {
  let short = simple_hash("x")
  let medium = simple_hash("medium_string")
  let long = simple_hash("this_is_a_very_long_string_for_testing_hash_function")
  
  // All should be different
  assert_false(short == medium)
  assert_false(medium == long)
  assert_false(short == long)
}

///|
test "simple_hash handles special characters" {
  let special1 = simple_hash("hello@world.com")
  let special2 = simple_hash("user-name_123")
  let special3 = simple_hash("path/to/file.txt")
  
  // Should handle special characters without issues and produce different hashes
  assert_false(special1 == special2)
  assert_false(special2 == special3)
  assert_false(special1 == special3)
}