///|
test "simple_hash empty string returns value" {
  let result = simple_hash("")
  inspect(result, content="5381")
}

///|
test "simple_hash same input same output" {
  let hash1 = simple_hash("test")
  let hash2 = simple_hash("test")
  inspect(hash1, content="2090756197")
  inspect(hash2, content="2090756197")
  assert_true(hash1 == hash2)
}

///|
test "simple_hash different inputs differ" {
  let hash_a = simple_hash("a")
  let hash_b = simple_hash("b")
  inspect(hash_a, content="177670")
  inspect(hash_b, content="177671")
  assert_false(hash_a == hash_b)
}