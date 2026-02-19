///|
pub fn create_app() -> @mars.Server {
  let app = @mars.Server::new()
  let api = @core.ApiState::new()
  app.get(
    "*",
    @mars.handler(fn(ctx) {
      let raw_path = ctx.path()
      let route = strip_query_and_hash(raw_path)
      if route == "/" {
        return ctx.html(render_home_page(), status=200)
      }
      if route == "/healthz" {
        return ctx.text(@core.healthz_text())
      }
      if route == "/readme" {
        return ctx.html(render_readme_page(api), status=200)
      }
      if route == "/filer" {
        let path = query_param(raw_path, "path").unwrap_or("")
        return ctx.html(render_filer_page(api, path), status=200)
      }
      if route == "/file" {
        let path = query_param(raw_path, "path").unwrap_or("")
        let page = render_file_page(api, path)
        return ctx.html(page.html, status=page.status)
      }
      ctx.text("Not Found", status=404)
    }),
  )
  app
}

///|
priv struct PageHtml {
  status : Int
  html : String
}

///|
fn render_home_page() -> String {
  render_layout("bithub", [
    @luna.h("h1", [], [@luna.text("bithub")]),
    @luna.h("p", [], [@luna.text("minimal github-like interface backed by bit kv.")]),
    @luna.h("ul", [], [
      @luna.h("li", [], [@components.link("/readme", [@luna.text("README.md")])]),
      @luna.h("li", [], [@components.link("/filer", [@luna.text("files")])]),
    ]),
  ])
}

///|
fn render_readme_page(api : @core.ApiState) -> String {
  let markdown = api.readme_markdown()
  let html = @markdown.md_to_html(markdown)
  render_layout("README.md", [
    @luna.h("h1", [], [@luna.text("README.md")]),
    @components.region(aria_label="README", [@luna.raw_html(html)]),
  ])
}

///|
fn render_filer_page(api : @core.ApiState, raw_path : String) -> String {
  let path = normalize_path(raw_path)
  let entries = api.list_entries(path)
  let display_path = if path.length() == 0 { "/" } else { "/" + path }
  let list_nodes : Array[@luna.Node[Unit, String]] = []
  for entry in entries {
    let href = if entry.is_dir {
      "/filer?path=" + entry.path
    } else {
      "/file?path=" + entry.path
    }
    let suffix = if entry.is_dir { "/" } else { "" }
    let label = if entry.is_dir {
      "[dir] " + entry.name + suffix
    } else {
      "[file] " + entry.name
    }
    list_nodes.push(
      @luna.h("li", [], [@components.link(href, [@luna.text(label)])]),
    )
  }
  if list_nodes.length() == 0 {
    list_nodes.push(@luna.h("li", [], [@luna.text("(empty)")]))
  }
  render_layout("filer", [
    @luna.h("h1", [], [@luna.text("filer")]),
    @luna.h("p", [], [@luna.text("path: " + display_path)]),
    @luna.h("ul", [], list_nodes),
  ])
}

///|
fn render_file_page(api : @core.ApiState, raw_path : String) -> PageHtml {
  let result = api.lookup_file(raw_path)
  match result.content {
    Some(content) => {
      let body_nodes = if is_markdown_path(result.path) {
        [
          @components.region(
            aria_label="file markdown",
            [@luna.raw_html(@markdown.md_to_html(content))],
          ),
        ]
      } else {
        [
          @components.region(aria_label="file source", [
            @luna.h("pre", [("class", @luna.attr_static("source-code"))], [
              @luna.h("code", [], [@luna.text(content)]),
            ]),
          ]),
        ]
      }
      let content_nodes : Array[@luna.Node[Unit, String]] = [
        @luna.h("h1", [], [@luna.text(result.path)]),
      ]
      for node in body_nodes {
        content_nodes.push(node)
      }
      { status: result.status, html: render_layout(result.path, content_nodes) }
    }
    None => {
      let missing_title = if result.path.length() == 0 { "file" } else { result.path }
      {
        status: result.status,
        html: render_layout(missing_title, [
          @luna.h("h1", [], [@luna.text(missing_title)]),
          @luna.h("p", [], [@luna.text("not found")]),
        ]),
      }
    }
  }
}

///|
fn render_layout(
  title : String,
  content : Array[@luna.Node[Unit, String]],
) -> String {
  let page = @luna.fragment([
    @components.banner([
      @luna.h("div", [("class", @luna.attr_static("site-banner"))], [
        @luna.h("strong", [("class", @luna.attr_static("site-title"))], [
          @luna.text("bithub"),
        ]),
        @luna.h(
          "nav",
          [
            ("class", @luna.attr_static("site-nav")),
            ("aria-label", @luna.attr_static("primary navigation")),
          ],
          [
            @components.link("/", [@luna.text("home")]),
            @luna.text(" | "),
            @components.link("/readme", [@luna.text("README")]),
            @luna.text(" | "),
            @components.link("/filer", [@luna.text("filer")]),
          ],
        ),
      ]),
    ]),
    @components.main_content([
      @components.region(aria_label="page content", content),
    ]),
    @components.contentinfo([@luna.text("rendered by sol + luna components")]),
  ])
  let css =
    #|:root{color-scheme:light dark;--bg:#f8fafc;--panel:#ffffff;--text:#0f172a;--link:#1d4ed8;--border:#d1d5db;--pre:#f3f4f6;}
    #|@media (prefers-color-scheme: dark){:root{--bg:#0b1220;--panel:#111a2e;--text:#dbe7ff;--link:#7cb3ff;--border:#2a3653;--pre:#0f172a;}}
    #|html{height:100%;}
    #|body{margin:0;height:100%;box-sizing:border-box;background:var(--bg);color:var(--text);font-family:ui-sans-serif,system-ui,sans-serif;padding:68px 14px 34px;}
    #|header{position:fixed;top:0;left:0;right:0;z-index:10;background:var(--panel);border-bottom:1px solid var(--border);padding:12px 14px;}
    #|.site-banner{display:flex;gap:10px;align-items:center;flex-wrap:wrap;}
    #|.site-title{font-size:18px;}
    #|main{max-width:980px;margin:0 auto;min-height:calc(100vh - 120px);background:var(--panel);border:1px solid var(--border);border-radius:8px;padding:16px;}
    #|footer{position:fixed;left:0;right:0;bottom:0;background:var(--panel);border-top:1px solid var(--border);padding:4px 14px;font-size:12px;}
    #|a{color:var(--link);}
    #|pre.source-code{overflow:auto;background:var(--pre);padding:12px;border-radius:6px;}
    #|code{font-family:ui-monospace,Menlo,monospace;}
    #|@media (max-width: 760px){body{padding:64px 10px 12px;height:auto;}main{min-height:auto;}footer{position:static;margin-top:12px;padding:8px 0 0;border-top:none;}}
  let head = "<meta charset=\"utf-8\"><style>" + css + "</style>"
  @sol.render_page(page, title~, head~)
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
fn is_markdown_path(path : String) -> Bool {
  path.has_suffix(".md") || path.has_suffix(".markdown")
}

///|
fn query_param(raw_path : String, key : String) -> String? {
  match query_string(raw_path) {
    None => None
    Some(query) => {
      for pair_view in query.split("&") {
        let pair = pair_view.to_string()
        if pair.length() == 0 {
          continue
        }
        match pair.find("=") {
          Some(i) => {
            let raw_key = String::unsafe_substring(pair, start=0, end=i)
            if @mars.url_decode(raw_key) == key {
              let raw_value = String::unsafe_substring(
                pair,
                start=i + 1,
                end=pair.length(),
              )
              return Some(@mars.url_decode(raw_value))
            }
          }
          None => {
            if @mars.url_decode(pair) == key {
              return Some("")
            }
          }
        }
      }
      None
    }
  }
}

///|
fn query_string(raw_path : String) -> String? {
  let query_pos = find_char(raw_path, '?')
  if query_pos < 0 {
    return None
  }
  let mut end = raw_path.length()
  let hash_pos = find_char(raw_path, '#')
  if hash_pos >= 0 && hash_pos > query_pos {
    end = hash_pos
  }
  let start = query_pos + 1
  if start >= end {
    Some("")
  } else {
    Some(String::unsafe_substring(raw_path, start~, end~))
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
test "home page is rendered by sol with luna landmarks" {
  let html = render_home_page()
  assert_true(html.contains("<header"))
  assert_true(html.contains("<main"))
  assert_true(html.contains("rendered by sol + luna components"))
  assert_true(html.contains("href=\"/readme\""))
}

///|
test "readme page renders markdown html" {
  let api = @core.ApiState::new()
  let html = render_readme_page(api)
  assert_true(html.contains("<h1>README.md</h1>"))
  assert_true(html.contains("<h1>bithub</h1>"))
}

///|
test "file page renders source and missing status" {
  let api = @core.ApiState::new()
  let found = render_file_page(api, "src/core/api_state.mbt")
  inspect(found.status, content="200")
  assert_true(found.html.contains("<pre class=\"source-code\"><code>"))
  assert_true(found.html.contains("pub struct ApiState"))

  let missing = render_file_page(api, "missing.txt")
  inspect(missing.status, content="404")
  assert_true(missing.html.contains("not found"))
}
