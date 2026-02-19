///|
fn parse_port(raw : String) -> Int {
  let parsed = @strconv.parse_int(raw) catch { _ => 8787 }
  if parsed > 0 {
    parsed
  } else {
    8787
  }
}

///|
pub struct CliOptions {
  repo : String
  port : Int
  enable_p2p : Bool
  p2p_command_template : String?
  catalog_path : String?
}

///|
fn parse_p2p_cmd_flag(arg : String) -> String? {
  let prefix = "--p2p-cmd="
  if arg.has_prefix(prefix) {
    Some(String::unsafe_substring(arg, start=prefix.length(), end=arg.length()))
  } else {
    None
  }
}

///|
fn parse_catalog_flag(arg : String) -> String? {
  let prefix = "--catalog="
  if arg.has_prefix(prefix) {
    Some(String::unsafe_substring(arg, start=prefix.length(), end=arg.length()))
  } else {
    None
  }
}

///|
pub fn parse_cli_options(argv : Array[String]) -> CliOptions {
  let positional : Array[String] = []
  let mut enable_p2p = false
  let mut p2p_command_template : String? = None
  let mut catalog_path : String? = None

  let mut idx = 2
  while idx < argv.length() {
    let arg = argv[idx]
    if arg == "--p2p" || arg == "--public" {
      enable_p2p = true
    } else if arg == "--p2p-cmd" {
      enable_p2p = true
      if idx + 1 < argv.length() {
        p2p_command_template = Some(argv[idx + 1])
        idx += 1
      }
    } else if parse_p2p_cmd_flag(arg) is Some(cmd) {
      enable_p2p = true
      p2p_command_template = Some(cmd)
    } else if arg == "--catalog" {
      if idx + 1 < argv.length() {
        catalog_path = Some(argv[idx + 1])
        idx += 1
      }
    } else if parse_catalog_flag(arg) is Some(path) {
      catalog_path = Some(path)
    } else if arg.has_prefix("--") {
      ()
    } else {
      positional.push(arg)
    }
    idx += 1
  }

  let has_catalog = catalog_path is Some(_)
  let repo = if has_catalog {
    "."
  } else if positional.length() > 0 {
    positional[0]
  } else {
    "."
  }
  let port_raw = if has_catalog {
    if positional.length() > 0 {
      positional[0]
    } else {
      "8787"
    }
  } else if positional.length() > 1 {
    positional[1]
  } else {
    "8787"
  }
  {
    repo,
    port: parse_port(port_raw),
    enable_p2p,
    p2p_command_template,
    catalog_path,
  }
}

///|
fn parse_args() -> CliOptions {
  parse_cli_options(@nprocess.argv())
}

///|
pub fn render_p2p_command(
  template : String,
  local_url : String,
  port : Int,
) -> String {
  template
  .replace(old="{url}", new=local_url)
  .replace(old="{port}", new=port.to_string())
}

///|
fn min_opt_int(a : Int?, b : Int?) -> Int? {
  match (a, b) {
    (Some(x), Some(y)) => Some(if x < y { x } else { y })
    (Some(x), None) => Some(x)
    (None, Some(y)) => Some(y)
    (None, None) => None
  }
}

///|
fn is_url_terminator(c : Char) -> Bool {
  c == ' ' ||
  c == '\t' ||
  c == '\r' ||
  c == '\n' ||
  c == '"' ||
  c == '\'' ||
  c == '<' ||
  c == '>' ||
  c == ')' ||
  c == ']' ||
  c == '}'
}

///|
pub fn extract_first_http_url(text : String) -> String? {
  let start = min_opt_int(text.find("https://"), text.find("http://"))
  match start {
    None => None
    Some(s) => {
      let tail = String::unsafe_substring(text, start=s, end=text.length())
      let end_rel = tail.find_by(is_url_terminator).unwrap_or(tail.length())
      if end_rel <= 0 {
        None
      } else {
        Some(String::unsafe_substring(tail, start=0, end=end_rel))
      }
    }
  }
}

///|
fn trim_trailing_slashes(path : String) -> String {
  let mut out = path
  while out.length() > 1 && out.has_suffix("/") {
    out = String::unsafe_substring(out, start=0, end=out.length() - 1)
  }
  out
}

///|
fn derive_catalog_name(path : String) -> String {
  let normalized = trim_trailing_slashes(path.trim(chars=" \n\r\t").to_string())
  if normalized == "." {
    return "."
  }
  match normalized.rev_find("/") {
    Some(i) if i + 1 < normalized.length() =>
      String::unsafe_substring(normalized, start=i + 1, end=normalized.length())
    _ => normalized
  }
}

///|
fn parse_catalog_line(line : String) -> (String, String)? {
  let normalized = line.trim(chars=" \n\r\t").to_string()
  if normalized.length() == 0 || normalized.has_prefix("#") {
    return None
  }
  match normalized.find("\t") {
    Some(i) => {
      let raw_name = String::unsafe_substring(normalized, start=0, end=i)
      let raw_path = String::unsafe_substring(
        normalized,
        start=i + 1,
        end=normalized.length(),
      )
      let path = raw_path.trim(chars=" \n\r\t").to_string()
      if path.length() == 0 {
        return None
      }
      let name = raw_name.trim(chars=" \n\r\t").to_string()
      if name.length() == 0 {
        Some((derive_catalog_name(path), path))
      } else {
        Some((name, path))
      }
    }
    None => {
      let path = normalized
      Some((derive_catalog_name(path), path))
    }
  }
}

///|
pub fn parse_catalog_text(text : String) -> Array[(String, String)] {
  let entries : Array[(String, String)] = []
  for line_view in text.split("\n") {
    let line = line_view.to_string()
    match parse_catalog_line(line) {
      Some(entry) => entries.push(entry)
      None => ()
    }
  }
  entries
}

///|
fn resolve_catalog_repo_path(
  catalog_path : String,
  repo_path : String,
) -> String {
  if @npath.isAbsolute(repo_path) {
    @npath.normalize(repo_path)
  } else {
    let base_dir = @npath.dirname(catalog_path)
    @npath.resolve([base_dir, repo_path])
  }
}

///|
priv struct CatalogRepo {
  id : String
  name : String
  root : String
  state : RepoState
}

///|
fn load_catalog_repos(catalog_path : String) -> Array[CatalogRepo] {
  let text = @nfs.read_file_as_string(catalog_path, encoding="utf-8") catch {
    _ => return []
  }
  let parsed = parse_catalog_text(text)
  let repos : Array[CatalogRepo] = []
  for i in 0..<parsed.length() {
    let id = "repo-" + (i + 1).to_string()
    let name = parsed[i].0
    let resolved_root = resolve_catalog_repo_path(catalog_path, parsed[i].1)
    let state = RepoState::new(resolved_root, route_base="/repo/" + id)
    repos.push({ id, name, root: resolved_root, state })
  }
  repos
}

///|
fn default_p2p_command_template() -> String {
  "npx --yes localtunnel --port {port}"
}

///|
fn resolve_p2p_command_template(options : CliOptions) -> String {
  match options.p2p_command_template {
    Some(cmd) => cmd
    None =>
      match @nprocess.env().get("BITHUB_P2P_CMD") {
        Some(env_cmd) => env_cmd
        None => default_p2p_command_template()
      }
  }
}

///|
extern "js" fn chunk_to_string(data : @js.Any) -> String =
  #|(data) => {
  #|  if (typeof data === "string") return data;
  #|  if (data && typeof data.toString === "function") return data.toString();
  #|  return String(data ?? "");
  #|}

///|
fn start_p2p_tunnel(
  options : CliOptions,
  host : String,
) -> @nchild.ChildProcess? {
  if not(options.enable_p2p) {
    return None
  }
  let local_url = "http://\{host}:\{options.port}"
  let template = resolve_p2p_command_template(options)
  let command = render_p2p_command(template, local_url, options.port)
  println("bithub p2p: starting tunnel")
  println("bithub p2p command: \{command}")

  let child = @nchild.spawn(command, shell=true)
  child.on_stdout_data(fn(data) {
    let chunk = chunk_to_string(data)
    if chunk.length() > 0 {
      ignore(@nprocess.stdout().write(@js.any(chunk)))
    }
    match extract_first_http_url(chunk) {
      Some(url) => println("bithub public: \{url}")
      None => ()
    }
  })
  child.on_stderr_data(fn(data) {
    let chunk = chunk_to_string(data)
    if chunk.length() > 0 {
      ignore(@nprocess.stderr().write(@js.any(chunk)))
    }
    match extract_first_http_url(chunk) {
      Some(url) => println("bithub public: \{url}")
      None => ()
    }
  })
  child.on_error(fn(_err) {
    ignore(
      @nprocess.stderr().write(@js.any("bithub p2p error: spawn failed\n")),
    )
  })
  child.on_close(fn(code, signal) {
    let code_text = match code {
      Some(c) => c.to_string()
      None => "null"
    }
    let signal_text = signal.unwrap_or("none")
    println("bithub p2p: stopped (code=\{code_text}, signal=\{signal_text})")
  })

  @nprocess.on("SIGINT", fn() { ignore(child.kill()) })
  @nprocess.on("SIGTERM", fn() { ignore(child.kill()) })

  Some(child)
}

///|
fn route_repo_response(state : RepoState, raw_url : String) -> PageResponse {
  if raw_url == "/" || raw_url.has_prefix("/?") || raw_url.has_prefix("/#") {
    return state.render_root()
  }
  if raw_url == "/issues" ||
    raw_url.has_prefix("/issues?") ||
    raw_url.has_prefix("/issues#") {
    return state.render_issues()
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
fn parse_catalog_repo_route(raw_url : String) -> (String, String)? {
  if not(raw_url.has_prefix("/repo/")) {
    return None
  }
  let rest = String::unsafe_substring(raw_url, start=6, end=raw_url.length())
  if rest.length() == 0 {
    return None
  }

  let mut repo_end = rest.length()
  for idx, c in rest {
    if c == '/' || c == '?' || c == '#' {
      repo_end = idx
      break
    }
  }
  if repo_end == 0 {
    return None
  }

  let repo_id = String::unsafe_substring(rest, start=0, end=repo_end)
  let route_prefix = "/repo/" + repo_id
  let suffix = if raw_url.length() > route_prefix.length() {
    String::unsafe_substring(
      raw_url,
      start=route_prefix.length(),
      end=raw_url.length(),
    )
  } else {
    ""
  }
  let normalized_suffix = if suffix.length() == 0 {
    "/"
  } else if suffix.has_prefix("?") || suffix.has_prefix("#") {
    "/" + suffix
  } else {
    suffix
  }
  Some((repo_id, normalized_suffix))
}

///|
fn find_catalog_repo(
  repos : Array[CatalogRepo],
  repo_id : String,
) -> CatalogRepo? {
  for repo in repos {
    if repo.id == repo_id {
      return Some(repo)
    }
  }
  None
}

///|
fn render_catalog_html(
  repos : Array[CatalogRepo],
  title : String,
  message? : String = "",
) -> String {
  let list = StringBuilder::new()
  if repos.length() == 0 {
    list.write_string("<p>No repositories in catalog.</p>")
  } else {
    list.write_string("<ul>")
    for repo in repos {
      list.write_string(
        "<li><a href=\"/repo/" +
        escape_html(repo.id) +
        "\">" +
        escape_html(repo.name) +
        "</a> <code>" +
        escape_html(shorten_home_prefix(repo.root)) +
        "</code></li>",
      )
    }
    list.write_string("</ul>")
  }

  let body = StringBuilder::new()
  body.write_string("<!doctype html><html><head><meta charset=\"utf-8\">")
  body.write_string("<title>bithub catalog</title>")
  body.write_string(
    "<style>:root{color-scheme:light dark;--bg:#f8fafc;--text:#0f172a;--panel:#ffffff;--border:#d1d5db;--link:#1d4ed8;}@media (prefers-color-scheme: dark){:root{--bg:#0b1220;--text:#dbe7ff;--panel:#111a2e;--border:#2a3653;--link:#7cb3ff;}}body{margin:0;padding:24px;font-family:ui-sans-serif,system-ui,sans-serif;background:var(--bg);color:var(--text);}main{max-width:980px;margin:0 auto;background:var(--panel);padding:16px;border:1px solid var(--border);border-radius:8px;}a{color:var(--link);}code{font-family:ui-monospace,Menlo,monospace;}</style>",
  )
  body.write_string("</head><body><main>")
  body.write_string("<h1>" + escape_html(title) + "</h1>")
  if message.length() > 0 {
    body.write_string("<p>" + escape_html(message) + "</p>")
  }
  body.write_string(list.to_string())
  body.write_string("</main></body></html>")
  body.to_string()
}

///|
fn route_catalog_response(
  repos : Array[CatalogRepo],
  raw_url : String,
) -> PageResponse {
  if raw_url == "/" || raw_url.has_prefix("/?") || raw_url.has_prefix("/#") {
    return { status: 200, html: render_catalog_html(repos, "bithub catalog") }
  }
  match parse_catalog_repo_route(raw_url) {
    Some((repo_id, repo_raw_url)) =>
      match find_catalog_repo(repos, repo_id) {
        Some(repo) => route_repo_response(repo.state, repo_raw_url)
        None =>
          {
            status: 404,
            html: render_catalog_html(
              repos,
              "bithub catalog",
              message="Unknown repository id: " + repo_id,
            ),
          }
      }
    None =>
      {
        status: 404,
        html: render_catalog_html(
          repos,
          "bithub catalog",
          message="Route not found.",
        ),
      }
  }
}

///|
priv enum AppState {
  Single(RepoState)
  Catalog(Array[CatalogRepo])
}

///|
fn route_response(app_state : AppState, raw_url : String) -> PageResponse {
  match app_state {
    Single(state) => route_repo_response(state, raw_url)
    Catalog(repos) => route_catalog_response(repos, raw_url)
  }
}

///|
fn configure_sol_app(app : @mars.Server, app_state : AppState) -> Unit {
  app.get(
    "*",
    @mars.handler(fn(ctx) {
      let response = route_response(app_state, ctx.path())
      ctx.html(response.html, status=response.status)
    }),
  )
}

///|
pub extern "js" fn ensure_sol_reschedule_symbol() -> Unit =
  #| () => {
  #|   const key = "moonbitlang$async$internal$event_loop$$reschedule";
  #|   if (typeof globalThis[key] !== "function") {
  #|     globalThis[key] = () => {};
  #|   }
  #| }

///|
fn main {
  let options = parse_args()
  let app_state = match options.catalog_path {
    Some(path) => Catalog(load_catalog_repos(path))
    None => Single(RepoState::new(options.repo))
  }
  let host = "127.0.0.1"
  let _p2p_tunnel = start_p2p_tunnel(options, host)
  ensure_sol_reschedule_symbol()
  @sol.run(
    fn(app) {
      configure_sol_app(app, app_state)
      println("bithub: http://\{host}:\{options.port}/")
      match app_state {
        Single(state) => println("repo: \{state.root}")
        Catalog(repos) => println("catalog repos: \{repos.length()}")
      }
    },
    port=options.port,
  )
}
