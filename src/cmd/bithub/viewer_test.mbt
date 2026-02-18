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
test "as_view_html falls back to markdown renderer for unknown extensions" {
  let html = as_view_html("src/main.unknown", "fn main {}")
  assert_true(html.contains("<pre"))
  assert_true(html.contains("fn main"))
}

///|
test "as_view_html highlights known code files with syntree" {
  let html = as_view_html("src/main.ts", "const x = 1")
  assert_true(html.contains("class=\"highlight"))
  assert_true(html.contains("color: #"))
}

///|
test "render_layout contains issues link" {
  let state = RepoState::new(".")
  let html = state.render_layout("README.md", "<p>ok</p>")
  assert_true(html.contains("href=\"/issues\""))
}

///|
test "render_layout uses split layout container" {
  let state = RepoState::new(".")
  let html = state.render_layout("README.md", "<p>ok</p>")
  assert_true(html.contains("class=\"split-layout\""))
}

///|
test "as_issues_html renders issue summaries" {
  let html = as_issues_html([issue_summary("issue-1", "Bug report", "open")])
  assert_true(html.contains("<h1>Issues</h1>"))
  assert_true(html.contains("issue-1"))
  assert_true(html.contains("Bug report"))
  assert_true(html.contains("open"))
}

///|
test "render_issues returns page response" {
  let state = RepoState::new(".")
  let page = state.render_issues()
  inspect(page.status, content="200")
  assert_true(page.html.contains("<h1>Issues</h1>"))
}

///|
test "scan_repo_files includes README.md in this repository" {
  let files = scan_repo_files(".", 400)
  assert_true(files.contains("README.md"))
}

///|
test "load_repo_issues returns empty for path without .git" {
  let issues = load_repo_issues("/__bithub_no_such_repo__", 10)
  inspect(issues.length(), content="0")
}
