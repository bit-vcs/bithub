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
test "ApiState renders README.md by markdown renderer" {
  let api = ApiState::new()
  let html = api.render_readme_html()
  assert_true(html.contains("<h1>"))
  assert_true(html.contains("bithub"))
}

///|
test "ApiState renders filer with minimum links" {
  let api = ApiState::new()
  let root = api.render_filer_html("")
  assert_true(root.contains("README.md"))
  assert_true(root.contains("/file?path=README.md"))
  assert_true(root.contains("moon.mod.json"))
  assert_true(root.contains("/file?path=moon.mod.json"))
  assert_true(root.contains("src"))
  assert_true(root.contains("/filer?path=src"))
  let core = api.render_filer_html("src/core")
  assert_true(core.contains("api_state.mbt"))
  assert_true(core.contains("/file?path=src/core/api_state.mbt"))
}

///|
test "ApiState renders file content and missing file status" {
  let api = ApiState::new()
  let found = api.render_file_response("src/core/api_state.mbt")
  inspect(found.status, content="200")
  assert_true(found.body.contains("pub struct ApiState"))
  let missing = api.render_file_response("missing.txt")
  inspect(missing.status, content="404")
  assert_true(missing.body.contains("not found"))
}
