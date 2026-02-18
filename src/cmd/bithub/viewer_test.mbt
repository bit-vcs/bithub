///|
test "sanitize_rel_path blocks traversal" {
  inspect(sanitize_rel_path("README.md"), content="Some(\"README.md\")")
  inspect(sanitize_rel_path("/src/main.mbt"), content="Some(\"src/main.mbt\")")
  inspect(sanitize_rel_path("../secret"), content="None")
  inspect(sanitize_rel_path("a/../../b"), content="None")
}

///|
test "extract_blob_path strips route prefix" {
  inspect(extract_blob_path("/blob/README.md"), content="README.md")
  inspect(
    extract_blob_path("/blob/src/core/core.mbt"),
    content="src/core/core.mbt",
  )
  inspect(extract_blob_path("/"), content="")
}

///|
test "as_view_html wraps non-markdown in fenced block" {
  let html = as_view_html("src/main.mbt", "fn main {}")
  assert_true(html.contains("<pre"))
  assert_true(html.contains("fn main"))
}
