///|
fn parse_port(raw : String) -> Int {
  @strconv.parse_int(raw) catch {
    _ => 8787
  }
}

///|
fn parse_args() -> (String, Int) {
  let argv = @nprocess.argv()
  let repo = if argv.length() > 2 { argv[2] } else { "." }
  let port_raw = if argv.length() > 3 { argv[3] } else { "8787" }
  (repo, parse_port(port_raw))
}

///|
fn route_response(state : RepoState, raw_url : String) -> PageResponse {
  if raw_url == "/" || raw_url.has_prefix("/?") || raw_url.has_prefix("/#") {
    return state.render_root()
  }
  if raw_url.has_prefix("/blob/") {
    let rel_path = extract_blob_path(raw_url)
    return state.render_blob(rel_path)
  }
  {
    status: 404,
    html: state.render_layout("(not found)", "<p>Route not found.</p>"),
  }
}

///|
fn main {
  let (repo_arg, port) = parse_args()
  let state = RepoState::new(repo_arg)
  let host = "127.0.0.1"
  let server = @nhttp.createServer(requestListener=fn(
    req : @nhttp.IncomingMessage,
    res : @nhttp.ServerResponse,
  ) {
    let raw_url_opt : String? = @js.identity_option(req.as_any()._get("url"))
    let raw_url = raw_url_opt.unwrap_or("/")
    let response = route_response(state, raw_url)
    res.set_statusCode(response.status)
    res.setHeader("content-type", "text/html; charset=utf-8")
    ignore(res.write(response.html))
    res.end()
  })
  let _ = server.listen(port, host~, callback=fn() {
    println("bithub: http://\{host}:\{port}/")
    println("repo: \{state.root}")
  })
}
