///|
pub struct FileEntry {
  name : String
  path : String
  is_dir : Bool
}

///|
pub struct HtmlResponse {
  status : Int
  body : String
}

///|
// Adapter: @bitfs.Fs -> @bitlib.WorkingTree
priv struct KvWorkingTree {
  fs : @bitfs.Fs
  backing_fs : &@bit.RepoFileSystem
  write_fs : &@bit.FileSystem
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with read_file(self, path) {
  self.fs.read_file(self.backing_fs, path)
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with write_file(self, path, data) {
  self.fs.write_file(path, data)
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with remove_file(self, path) {
  self.fs.remove_file(path)
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with is_file(self, path) {
  self.fs.is_file(self.backing_fs, path)
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with is_dir(self, path) {
  self.fs.is_dir(self.backing_fs, path)
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with readdir(self, path) {
  self.fs.readdir(self.backing_fs, path)
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with is_dirty(self) {
  self.fs.is_dirty()
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with rollback(self) {
  self.fs.rollback()
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with get_working_files(self) {
  self.fs.get_working_files()
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with snapshot(
  self,
  message,
  author,
  timestamp,
) {
  let snapshot = self.fs.snapshot(
    self.write_fs,
    self.backing_fs,
    message,
    author,
    timestamp,
  )
  snapshot.commit_id
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with checkout(self, commit_id) {
  self.fs.checkout_snapshot(self.backing_fs, commit_id)
}

///|
// Adapter: filesystem object db -> @bitlib.ObjectStore
priv struct KvObjectStore {
  backing_fs : &@bit.RepoFileSystem
  write_fs : &@bit.FileSystem
  git_dir : String
}

///|
impl @bitlib.ObjectStore for KvObjectStore with get(self, id) {
  let db = @bitlib.ObjectDb::load(self.backing_fs, self.git_dir)
  db.get(self.backing_fs, id)
}

///|
impl @bitlib.ObjectStore for KvObjectStore with put(self, obj_type, data) {
  @bitlib.write_loose_object(self.write_fs, self.git_dir, obj_type, data)
}

///|
impl @bitlib.ObjectStore for KvObjectStore with has(self, id) {
  let db = @bitlib.ObjectDb::load(self.backing_fs, self.git_dir) catch {
    _ => return false
  }
  let obj = db.get(self.backing_fs, id) catch { _ => return false }
  obj is Some(_)
}

///|
pub struct ApiState {
  kv : @kv.Kv
}

///|
pub fn ApiState::new() -> ApiState {
  let fs = @bit.TestFs::new()
  let bit_fs = @bitfs.Fs::empty("/repo/.git")
  let tree : KvWorkingTree = { fs: bit_fs, backing_fs: fs, write_fs: fs }
  let store : KvObjectStore = {
    backing_fs: fs,
    write_fs: fs,
    git_dir: "/repo/.git",
  }
  let kv = @kv.Kv::new(
    @kv.NodeId::new("bithub"),
    tree,
    store,
    @bit.ObjectId::zero(),
  )
  seed_files(kv)
  { kv, }
}

///|
pub fn ApiState::render_home_html(_self : ApiState) -> String {
  let body =
    #|<h1>bithub</h1>
    #|<p>minimal github-like interface backed by bit kv.</p>
    #|<ul>
    #|  <li><a href="/readme">README.md</a></li>
    #|  <li><a href="/filer">files</a></li>
    #|</ul>
  wrap_page("bithub", body)
}

///|
pub fn ApiState::render_readme_html(self : ApiState) -> String {
  let md = self.file_text("README.md").unwrap_or("# README.md\n\nnot found")
  let html = @markdown.md_to_html(md)
  wrap_page("README.md", "<article>" + html + "</article>")
}

///|
pub fn ApiState::render_filer_html(
  self : ApiState,
  raw_path : String,
) -> String {
  let path = normalize_path(raw_path)
  let entries = self.list_entries(path)
  let buf = StringBuilder::new()
  buf.write_string("<h1>filer</h1>")
  if path.length() == 0 {
    buf.write_string("<p>path: /</p>")
  } else {
    buf.write_string("<p>path: /" + escape_html(path) + "</p>")
  }
  buf.write_string("<ul>")
  for entry in entries {
    if entry.is_dir {
      buf.write_string(
        "<li>[dir] <a href=\"/filer?path=" +
        escape_html(entry.path) +
        "\">" +
        escape_html(entry.name) +
        "/</a></li>",
      )
    } else {
      buf.write_string(
        "<li>[file] <a href=\"/file?path=" +
        escape_html(entry.path) +
        "\">" +
        escape_html(entry.name) +
        "</a></li>",
      )
    }
  }
  if entries.length() == 0 {
    buf.write_string("<li>(empty)</li>")
  }
  buf.write_string("</ul>")
  wrap_page("filer", buf.to_string())
}

///|
pub fn ApiState::render_file_response(
  self : ApiState,
  raw_path : String,
) -> HtmlResponse {
  let path = normalize_path(raw_path)
  if path.length() == 0 {
    return {
      status: 404,
      body: wrap_page("file", "<h1>file</h1><p>not found</p>"),
    }
  }
  match self.file_text(path) {
    Some(content) => {
      let body = "<h1>" +
        escape_html(path) +
        "</h1><pre>" +
        escape_html(content) +
        "</pre>"
      { status: 200, body: wrap_page(path, body) }
    }
    None => {
      let body = "<h1>" + escape_html(path) + "</h1><p>not found</p>"
      { status: 404, body: wrap_page(path, body) }
    }
  }
}

///|
pub fn ApiState::list_entries(
  self : ApiState,
  raw_path : String,
) -> Array[FileEntry] {
  let path = normalize_path(raw_path)
  let names = self.kv.list(path)
  names.sort_by(fn(a, b) { String::compare(a, b) })
  let entries : Array[FileEntry] = []
  for name in names {
    let full_path = join_path(path, name)
    entries.push({ name, path: full_path, is_dir: not(self.kv.has(full_path)) })
  }
  entries
}

///|
pub fn ApiState::file_text(self : ApiState, raw_path : String) -> String? {
  let path = normalize_path(raw_path)
  match self.kv.get(path) {
    Some(bytes) => Some(@utf8.decode_lossy(bytes))
    None => None
  }
}

///|
fn seed_files(kv : @kv.Kv) -> Unit {
  let readme =
    #|# bithub
    #|
    #|A minimal self-browsing API/UI prototype powered by `bit kv`.
    #|
    #|- open `/filer` to browse this app
    #|- open `/file?path=src/core/api_state.mbt` to inspect core source
  kv.set_string("README.md", readme)
  let moon_mod =
    #|{
    #|  "name": "bit-vcs/bithub",
    #|  "preferred-target": "js",
    #|  "deps": {
    #|    "mizchi/bit": "0.21.2",
    #|    "mizchi/markdown": "0.4.7",
    #|    "mizchi/mars": "0.3.7"
    #|  }
    #|}
  kv.set_string("moon.mod.json", moon_mod)
  let core_source =
    #|pub struct RouteSpec {
    #|  id : String
    #|  http_method : String
    #|  path : String
    #|}
    #|
    #|pub fn mars_route_specs() -> Array[RouteSpec] {
    #|  [
    #|    { id: "home", http_method: "GET", path: "/" },
    #|    { id: "readme", http_method: "GET", path: "/readme" },
    #|    { id: "filer", http_method: "GET", path: "/filer" },
    #|  ]
    #|}
  kv.set_string("src/core/core.mbt", core_source)
  let api_state_source =
    #|pub struct ApiState {
    #|  kv : @kv.Kv
    #|}
    #|
    #|pub fn ApiState::render_filer_html(self : ApiState, path : String) -> String {
    #|  let entries = self.list_entries(path)
    #|  // minimal html
    #|  "<h1>filer</h1>"
    #|}
  kv.set_string("src/core/api_state.mbt", api_state_source)
  let mars_adapter =
    #|pub fn create_app() -> @mars.Server {
    #|  let app = @mars.Server::new()
    #|  let api = @core.ApiState::new()
    #|  let _ = app
    #|    ..get("/", fn(ctx) { ctx.html(api.render_home_html()) })
    #|    ..get("/filer", fn(ctx) { ctx.html(api.render_filer_html("")) })
    #|  app
    #|}
  kv.set_string("src/adapters/mars_http/server.mbt", mars_adapter)
  let main_entry =
    #|pub fn fetch(
    #|  request : @mars.JsRequest,
    #|  env : @mars.JsEnv,
    #|  exec_ctx : @mars.JsExecCtx,
    #|) -> @js_async.Promise[@mars.JsResponse] {
    #|  let app = @mars_http.create_app()
    #|  let handler = app.to_handler_with_env(env, exec_ctx)
    #|  handler(request)
    #|}
  kv.set_string("src/cmd/main/main.mbt", main_entry)
  let notes =
    #|Mars/Sol boundary note:
    #|- keep core pure
    #|- keep adapter replaceable
    #|- cloudflare js target first
  kv.set_string("docs/notes.txt", notes)
}

///|
fn normalize_path(path : String) -> String {
  let mut p = path
  while p.length() > 0 && p.has_prefix("/") {
    p = String::unsafe_substring(p, start=1, end=p.length())
  }
  while p.length() > 0 && p.has_suffix("/") {
    p = String::unsafe_substring(p, start=0, end=p.length() - 1)
  }
  p
}

///|
fn join_path(parent : String, child : String) -> String {
  if parent.length() == 0 {
    child
  } else {
    parent + "/" + child
  }
}

///|
fn wrap_page(title : String, body_html : String) -> String {
  let style =
    #|body{font-family:ui-monospace,Menlo,monospace;max-width:900px;margin:24px auto;padding:0 12px;}
    #|nav{margin-bottom:12px;}
    #|pre{background:#f6f8fa;padding:12px;overflow:auto;}
  let nav =
    #|<nav>
    #|  <a href="/">home</a> |
    #|  <a href="/readme">README</a> |
    #|  <a href="/filer">filer</a>
    #|</nav>
  "<!doctype html><html><head><meta charset=\"utf-8\"><title>" +
  escape_html(title) +
  "</title><style>" +
  style +
  "</style></head><body>" +
  nav +
  "<main>" +
  body_html +
  "</main></body></html>"
}

///|
fn escape_html(raw : String) -> String {
  let buf = StringBuilder::new()
  for c in raw {
    match c {
      '&' => buf.write_string("&amp;")
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      '"' => buf.write_string("&quot;")
      '\'' => buf.write_string("&#39;")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}
