///|
pub struct PageResponse {
  status : Int
  html : String
}

///|
pub struct RepoState {
  root : String
  files : Array[String]
  initial_path : String
}

///|
pub fn RepoState::new(root : String) -> RepoState {
  let resolved = @npath.resolve([root])
  let files = collect_repo_files(resolved, 240)
  files.sort_by(fn(a, b) { String::compare(a, b) })
  let initial_path = if files.contains("README.md") {
    "README.md"
  } else if files.length() > 0 {
    files[0]
  } else {
    ""
  }
  { root: resolved, files, initial_path }
}

///|
pub fn RepoState::render_root(self : RepoState) -> PageResponse {
  if self.initial_path.length() == 0 {
    return {
      status: 200,
      html: self.render_layout("(empty)", "<p>No viewable files found.</p>"),
    }
  }
  self.render_blob(self.initial_path)
}

///|
pub fn RepoState::render_blob(
  self : RepoState,
  raw_path : String,
) -> PageResponse {
  let sanitized = sanitize_rel_path(raw_path)
  match sanitized {
    Some(rel_path) =>
      match read_repo_file(self.root, rel_path) {
        Some(content) => {
          let body_html = as_view_html(rel_path, content)
          { status: 200, html: self.render_layout(rel_path, body_html) }
        }
        None => {
          let body_html = "<p>File not found: " + rel_path + "</p>"
          { status: 404, html: self.render_layout(rel_path, body_html) }
        }
      }
    None => {
      let body_html = "<p>Invalid path.</p>"
      { status: 400, html: self.render_layout("(invalid)", body_html) }
    }
  }
}

///|
pub fn RepoState::render_layout(
  self : RepoState,
  selected_path : String,
  body_html : String,
) -> String {
  let header_nodes : Array[@luna.Node[Unit, String]] = [
    @components.link("/", [@luna.text("bithub")]),
    @luna.text(" : " + self.root),
  ]
  let nav_nodes = build_nav_nodes(self.files, selected_path)
  let main_nodes : Array[@luna.Node[Unit, String]] = [
    @components.breadcrumb_from_path("/blob", [], selected_path),
    @components.region(aria_label="file content", [@luna.raw_html(body_html)]),
  ]
  let footer_nodes : Array[@luna.Node[Unit, String]] = [
    @luna.text("luna components minimal file viewer"),
  ]
  let page = @components.page_layout(
    header=header_nodes,
    nav_content=nav_nodes,
    main_nodes,
    footer_content=footer_nodes,
  )
  let css =
    #|body{font-family:ui-sans-serif,system-ui,sans-serif;margin:0;padding:12px;line-height:1.4;}
    #|nav a{display:block;text-decoration:none;padding:2px 0;}
    #|main{margin-top:12px;}
    #|pre{background:#f6f8fa;padding:12px;overflow:auto;}
    #|code{font-family:ui-monospace,Menlo,monospace;}
  let doc = @lstatic.document(
    head_children=[
      @lstatic.meta(charset="utf-8"),
      @lstatic.title("bithub"),
      @lstatic.style_(css),
    ],
    body_children=[page],
  )
  @lstatic.render_document(doc)
}

///|
fn build_nav_nodes(
  files : Array[String],
  selected_path : String,
) -> Array[@luna.Node[Unit, String]] {
  let nodes : Array[@luna.Node[Unit, String]] = []
  let limit = if files.length() < 120 { files.length() } else { 120 }
  for i in 0..<limit {
    let path = files[i]
    let label = if path == selected_path { "[*] " + path } else { path }
    nodes.push(
      @components.link("/blob/" + path, disabled=path == selected_path, [
        @luna.text(label),
      ]),
    )
  }
  if files.length() > limit {
    nodes.push(@luna.text("..."))
  }
  nodes
}

///|
fn collect_repo_files(root : String, limit : Int) -> Array[String] {
  let out : Array[String] = []
  collect_repo_files_recursive(root, "", out, limit)
  out
}

///|
priv enum EntryKind {
  Dir
  File
  Other
}

///|
fn path_kind(abs_path : String) -> EntryKind {
  let st = @nfs.stat_sync(abs_path) catch { _ => return Other }
  if st.isDirectory() {
    Dir
  } else if st.isFile() {
    File
  } else {
    Other
  }
}

///|
fn collect_repo_files_recursive(
  root : String,
  rel_dir : String,
  out : Array[String],
  limit : Int,
) -> Unit {
  if out.length() >= limit {
    return
  }
  let abs_dir = if rel_dir.length() == 0 {
    root
  } else {
    @npath.join2(root, rel_dir)
  }
  let names = @nfs.readdir_sync(abs_dir) catch { _ => [] }
  names.sort_by(fn(a, b) { String::compare(a, b) })
  for name in names {
    if out.length() >= limit {
      return
    }
    if not(should_skip_name(name)) {
      let rel_path = if rel_dir.length() == 0 {
        name
      } else {
        rel_dir + "/" + name
      }
      let abs_path = @npath.join2(root, rel_path)
      match path_kind(abs_path) {
        Dir => collect_repo_files_recursive(root, rel_path, out, limit)
        File => if is_viewable_file(rel_path) { out.push(rel_path) }
        Other => ()
      }
    }
  }
}

///|
fn should_skip_name(name : String) -> Bool {
  name == ".git" ||
  name == ".mooncakes" ||
  name == "_build" ||
  name == "target" ||
  name == "node_modules"
}

///|
fn is_viewable_file(path : String) -> Bool {
  if path.has_suffix(".png") ||
    path.has_suffix(".jpg") ||
    path.has_suffix(".jpeg") ||
    path.has_suffix(".gif") ||
    path.has_suffix(".webp") ||
    path.has_suffix(".wasm") {
    return false
  }
  true
}

///|
fn read_repo_file(root : String, rel_path : String) -> String? {
  let abs_path = @npath.join2(root, rel_path)
  let text = @nfs.read_file_as_string(abs_path, encoding="utf-8") catch {
    _ => return None
  }
  Some(text)
}

///|
pub fn sanitize_rel_path(raw_path : String) -> String? {
  let mut path = raw_path
  while path.has_prefix("/") {
    path = String::unsafe_substring(path, start=1, end=path.length())
  }
  while path.has_prefix("./") {
    path = String::unsafe_substring(path, start=2, end=path.length())
  }
  if path.length() == 0 {
    return None
  }
  if path.contains("..") {
    return None
  }
  Some(path)
}

///|
pub fn extract_blob_path(route_path : String) -> String {
  let plain = strip_query_and_hash(route_path)
  if plain.has_prefix("/blob/") {
    String::unsafe_substring(plain, start=6, end=plain.length())
  } else {
    ""
  }
}

///|
fn strip_query_and_hash(path : String) -> String {
  let query_pos = find_char(path, '?')
  let hash_pos = find_char(path, '#')
  let mut end = path.length()
  if query_pos >= 0 && query_pos < end {
    end = query_pos
  }
  if hash_pos >= 0 && hash_pos < end {
    end = hash_pos
  }
  if end < path.length() {
    String::unsafe_substring(path, start=0, end~)
  } else {
    path
  }
}

///|
fn find_char(s : String, target : Char) -> Int {
  let mut idx = 0
  for c in s {
    if c == target {
      return idx
    }
    idx += 1
  }
  -1
}

///|
pub fn as_view_html(path : String, content : String) -> String {
  if path.has_suffix(".md") || path.has_suffix(".markdown") {
    return @markdown.md_to_html(content)
  }
  @markdown.md_to_html("```text\n" + content + "\n```")
}
