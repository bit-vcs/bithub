///|
test "sanitize_rel_path blocks traversal" {
  debug_inspect(sanitize_rel_path("README.md"), content="Some(\"README.md\")")
  debug_inspect(sanitize_rel_path("/src/main.mbt"), content="Some(\"src/main.mbt\")")
  debug_inspect(sanitize_rel_path("../secret"), content="None")
  debug_inspect(sanitize_rel_path("a/../../b"), content="None")
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
test "render_layout supports route_base for catalog repo pages" {
  let state = RepoState::new(".", route_base="/repo/repo-1")
  let html = state.render_layout("README.md", "<p>ok</p>")
  assert_true(html.contains("href=\"/repo/repo-1/issues\""))
  assert_true(html.contains("/repo/repo-1"))
}

///|
test "render_layout uses split layout container" {
  let state = RepoState::new(".")
  let html = state.render_layout("README.md", "<p>ok</p>")
  assert_true(html.contains("class=\"split-layout\""))
  assert_true(html.contains("class=\"split-resizer\""))
  assert_true(html.contains("role=\"separator\""))
}

///|
test "render_layout includes dark mode css" {
  let state = RepoState::new(".")
  let html = state.render_layout("README.md", "<p>ok</p>")
  assert_true(html.contains("prefers-color-scheme: dark"))
}

///|
test "render_layout uses collapsible tree for filer" {
  let state = RepoState::new(".")
  let html = state.render_layout("src/cmd/bithub/main.mbt", "<p>ok</p>")
  assert_true(html.contains("role=\"tree\""))
  assert_true(html.contains("role=\"treeitem\""))
  assert_true(html.contains("nav ul[role=tree]"))
  assert_true(html.contains("class=\"file-tree-icon file-tree-icon-dir\""))
  assert_true(html.contains("class=\"file-tree-icon file-tree-icon-file\""))
  assert_true(html.contains("class=\"file-tree-dir\""))
  assert_true(html.contains("data-tree-path=\"src\""))
  assert_true(html.contains("[*] main.mbt"))
  assert_true(!(html.contains("[*] src/cmd/bithub/main.mbt")))
  assert_true(html.contains("<summary"))
}

///|
test "replace_path_prefix_with_tilde shortens home path" {
  assert_true(
    replace_path_prefix_with_tilde(
      "/Users/mz/ghq/github.com/bit-vcs/bithub", "/Users/mz",
    ) ==
    "~/ghq/github.com/bit-vcs/bithub",
  )
  assert_true(
    replace_path_prefix_with_tilde(
      "/Users/mz/ghq/github.com/bit-vcs/bithub", "/Users/mz/",
    ) ==
    "~/ghq/github.com/bit-vcs/bithub",
  )
  assert_true(
    replace_path_prefix_with_tilde("/tmp/workspace", "/Users/mz") ==
    "/tmp/workspace",
  )
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
extern "js" fn create_repo_scan_fixture(path : String) -> Unit =
  #| (path) => {
  #|   const fs = require("node:fs")
  #|   fs.rmSync(path, { recursive: true, force: true })
  #|   fs.mkdirSync(path, { recursive: true })
  #|   fs.writeFileSync(path + "/README.md", "# test fixture")
  #| }

///|
extern "js" fn remove_repo_scan_fixture(path : String) -> Unit =
  #| (path) => { require("node:fs").rmSync(path, { recursive: true, force: true }) }

///|
test "scan_repo_files includes files from an isolated fixture" {
  let root = "/tmp/bithub-repo-scan-test"
  create_repo_scan_fixture(root)
  let files = scan_repo_files(root, 400)
  assert_true(files.contains("README.md"))
  remove_repo_scan_fixture(root)
}

///|
test "load_repo_issues returns empty for path without .git" {
  let issues = load_repo_issues("/__bithub_no_such_repo__", 10)
  inspect(issues.length(), content="0")
}
