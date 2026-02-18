///|
pub struct PageResponse {
  status : Int
  html : String
}

///|
pub struct IssueSummary {
  id : String
  title : String
  state : String
}

///|
pub fn issue_summary(
  id : String,
  title : String,
  state : String,
) -> IssueSummary {
  { id, title, state }
}

///|
pub struct RepoState {
  root : String
  files : Array[String]
  initial_path : String
  issues : Array[IssueSummary]
}

///|
pub fn RepoState::new(root : String) -> RepoState {
  let resolved = @npath.resolve([root])
  let files = scan_repo_files(resolved, 240)
  let issues = load_repo_issues(resolved, 120)
  let initial_path = select_initial_path(files)
  { root: resolved, files, initial_path, issues }
}

///|
fn select_initial_path(files : Array[String]) -> String {
  if files.contains("README.md") {
    "README.md"
  } else if files.length() > 0 {
    files[0]
  } else {
    ""
  }
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
      match load_repo_file(self.root, rel_path) {
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
pub fn RepoState::render_issues(self : RepoState) -> PageResponse {
  {
    status: 200,
    html: self.render_layout("(issues)", as_issues_html(self.issues)),
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
    @luna.text(" | "),
    @components.link("/issues", [@luna.text("issues")]),
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
  let page = @luna.fragment([
    @components.banner(header_nodes),
    @luna.h("div", [("class", @luna.attr_static("split-layout"))], [
      @luna.h("aside", [("class", @luna.attr_static("file-sidebar"))], [
        @components.nav(aria_label="repository files", nav_nodes),
      ]),
      @components.main_content(main_nodes),
    ]),
    @components.contentinfo(footer_nodes),
  ])
  let css =
    #|html{height:100%;overflow:hidden;}
    #|body{height:100%;box-sizing:border-box;font-family:ui-sans-serif,system-ui,sans-serif;margin:0;padding:72px 12px 28px;line-height:1.4;overflow:hidden;}
    #|header{position:fixed;top:0;left:0;right:0;z-index:20;background:#fff;padding:12px;border-bottom:1px solid #ddd;}
    #|footer{position:fixed;left:0;right:0;bottom:0;z-index:20;background:#fff;padding:4px 12px;border-top:1px solid #ddd;font-size:12px;}
    #|.split-layout{display:grid;grid-template-columns:minmax(220px,34ch) minmax(0,1fr);gap:16px;align-items:stretch;height:calc(100vh - 100px);overflow:hidden;}
    #|.file-sidebar{height:100%;min-height:0;overflow-y:auto;padding-right:8px;border-right:1px solid #ddd;}
    #|.split-layout main{min-width:0;min-height:0;overflow:auto;}
    #|nav a{display:block;text-decoration:none;padding:2px 0;}
    #|pre{background:#f6f8fa;padding:12px;overflow:auto;}
    #|code{font-family:ui-monospace,Menlo,monospace;}
    #|@media (max-width: 900px){html,body{height:auto;}body{padding-top:68px;padding-bottom:12px;overflow:auto;}footer{position:static;padding:8px 0 0;border-top:none;font-size:inherit;}.split-layout{display:flex;flex-direction:column;gap:12px;height:auto;overflow:visible;}.split-layout main{order:1;overflow:visible;}.file-sidebar{order:2;height:auto;overflow:visible;padding-right:0;border-right:none;border-top:1px solid #ddd;padding-top:8px;}}
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
pub fn as_issues_html(issues : Array[IssueSummary]) -> String {
  let buf = StringBuilder::new()
  buf.write_string("<h1>Issues</h1>")
  if issues.length() == 0 {
    buf.write_string("<p>No issues found.</p>")
    return buf.to_string()
  }
  buf.write_string("<ul>")
  for issue in issues {
    buf.write_string(
      "<li><code>" +
      escape_html(issue.id) +
      "</code> " +
      escape_html(issue.title) +
      " <strong>(" +
      escape_html(issue.state) +
      ")</strong></li>",
    )
  }
  buf.write_string("</ul>")
  buf.to_string()
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
  match highlight_source_with_syntree(path, content) {
    Some(highlighted) => highlighted
    None => @markdown.md_to_html("```text\n" + content + "\n```")
  }
}

///|
fn highlight_source_with_syntree(path : String, content : String) -> String? {
  if path.has_suffix(".ts") ||
    path.has_suffix(".tsx") ||
    path.has_suffix(".js") ||
    path.has_suffix(".jsx") {
    return Some(@mdsyntree.highlight_typescript(content))
  }
  if path.has_suffix(".mbt") {
    return Some(@mdsyntree.highlight_moonbit(content))
  }
  if path.has_suffix(".json") {
    return Some(@mdsyntree.highlight_json(content))
  }
  if path.has_suffix(".html") ||
    path.has_suffix(".htm") ||
    path.has_suffix(".xml") {
    return Some(@mdsyntree.highlight_html(content))
  }
  if path.has_suffix(".css") ||
    path.has_suffix(".scss") ||
    path.has_suffix(".less") {
    return Some(@mdsyntree.highlight_css(content))
  }
  if path.has_suffix(".sh") ||
    path.has_suffix(".bash") ||
    path.has_suffix(".zsh") ||
    path.has_suffix(".env") {
    return Some(@mdsyntree.highlight_bash(content))
  }
  if path.has_suffix(".rs") {
    return Some(@mdsyntree.highlight_rust(content))
  }
  None
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
