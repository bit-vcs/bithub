///|
test "mars_route_specs contains API routes" {
  let routes = mars_route_specs()
  inspect(routes.length(), content="5")
  inspect(routes[0].http_method, content="GET")
  inspect(routes[0].path, content="/")
  inspect(routes[1].http_method, content="GET")
  inspect(routes[1].path, content="/healthz")
  inspect(routes[2].path, content="/readme")
  inspect(routes[3].path, content="/filer")
  inspect(routes[4].path, content="/file")
}

///|
test "texts are stable for adapter boundary" {
  inspect(home_text(), content="bithub: mars-first bootstrap")
  inspect(healthz_text(), content="ok")
}

///|
test "ApiState exposes README markdown text" {
  let api = ApiState::new()
  let markdown = api.readme_markdown()
  assert_true(markdown.contains("# bithub"))
  assert_true(markdown.contains("minimal self-browsing API"))
}

///|
test "ApiState lists filer entries as data" {
  let api = ApiState::new()
  let root = api.list_entries("")
  assert_true(root.any(fn(entry) { entry.name == "README.md" && not(entry.is_dir) }))
  assert_true(root.any(fn(entry) { entry.name == "moon.mod.json" && not(entry.is_dir) }))
  assert_true(root.any(fn(entry) { entry.name == "src" && entry.is_dir }))

  let core = api.list_entries("src/core")
  assert_true(
    core.any(fn(entry) {
      entry.name == "api_state.mbt" &&
      entry.path == "src/core/api_state.mbt" &&
      not(entry.is_dir)
    }),
  )
}

///|
test "ApiState lookup_file returns content with status" {
  let api = ApiState::new()
  let found = api.lookup_file("src/core/api_state.mbt")
  inspect(found.status, content="200")
  assert_eq(found.path, "src/core/api_state.mbt")
  assert_true(
    match found.content {
      Some(text) => text.contains("pub struct ApiState")
      None => false
    },
  )

  let missing = api.lookup_file("missing.txt")
  inspect(missing.status, content="404")
  assert_eq(missing.path, "missing.txt")
  assert_eq(missing.content, None)

  let empty = api.lookup_file("")
  inspect(empty.status, content="404")
  assert_eq(empty.content, None)
}
