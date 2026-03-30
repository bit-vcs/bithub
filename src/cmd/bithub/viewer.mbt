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
  route_base : String
}

///|
pub fn RepoState::new(root : String, route_base? : String = "") -> RepoState {
  let resolved = @npath.resolve([root])
  let files = scan_repo_files(resolved, 240)
  let issues = load_repo_issues(resolved, 120)
  let initial_path = select_initial_path(files)
  {
    root: resolved,
    files,
    initial_path,
    issues,
    route_base: normalize_route_base(route_base),
  }
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
  let display_root = shorten_home_prefix(self.root)
  let root_route = route_root(self.route_base)
  let issues_route = route_issues(self.route_base)
  let blob_route_prefix = route_blob_prefix(self.route_base)
  let header_nodes : Array[@luna.Node[Unit, String]] = [
    @components.link(root_route, [@luna.text("bithub")]),
    @luna.text(" | "),
    @components.link(issues_route, [@luna.text("issues")]),
    @luna.text(" : " + display_root),
  ]
  let nav_nodes = build_nav_nodes(self.files, selected_path, blob_route_prefix)
  let main_nodes : Array[@luna.Node[Unit, String]] = [
    @components.breadcrumb_from_path(blob_route_prefix, [], selected_path),
    @components.region(aria_label="file content", [@luna.raw_html(body_html)]),
  ]
  let footer_nodes : Array[@luna.Node[Unit, String]] = [
    @luna.text("luna components minimal file viewer"),
  ]
  let page = @luna.fragment([
    @components.banner(header_nodes),
    @luna.h("div", [("class", @luna.attr_static("split-layout"))], [
      @luna.h(
        "aside",
        [
          ("class", @luna.attr_static("file-sidebar")),
          ("id", @luna.attr_static("file-sidebar")),
        ],
        [@components.nav(aria_label="repository files", nav_nodes)],
      ),
      @luna.h(
        "div",
        [
          ("class", @luna.attr_static("split-resizer")),
          ("role", @luna.attr_static("separator")),
          ("aria-orientation", @luna.attr_static("vertical")),
          ("aria-controls", @luna.attr_static("file-sidebar")),
          ("aria-label", @luna.attr_static("Resize file list pane")),
          ("tabindex", @luna.attr_static("0")),
        ],
        [],
      ),
      @components.main_content(main_nodes),
    ]),
    @components.contentinfo(footer_nodes),
    @luna.raw_html("<script>" + tree_keyboard_script() + "</script>"),
    @luna.raw_html("<script>" + split_resizer_script() + "</script>"),
  ])
  let css =
    #|:root{color-scheme:light dark;--bg:#f8fafc;--text:#0f172a;--panel:#ffffff;--border:#d1d5db;--link:#1d4ed8;--link-visited:#6d28d9;--pre-bg:#f3f4f6;--tree-guide:#93a7c9;}
    #|@media (prefers-color-scheme: dark){:root{--bg:#0b1220;--text:#dbe7ff;--panel:#111a2e;--border:#2a3653;--link:#7cb3ff;--link-visited:#b79cff;--pre-bg:#0f172a;--tree-guide:#334567;}}
    #|html{height:100%;overflow:hidden;}
    #|body{height:100%;box-sizing:border-box;font-family:ui-sans-serif,system-ui,sans-serif;margin:0;padding:72px 12px 28px;line-height:1.4;overflow:hidden;background:var(--bg);color:var(--text);}
    #|header{position:fixed;top:0;left:0;right:0;z-index:20;background:var(--panel);padding:12px;border-bottom:1px solid var(--border);}
    #|footer{position:fixed;left:0;right:0;bottom:0;z-index:20;background:var(--panel);padding:4px 12px;border-top:1px solid var(--border);font-size:12px;}
    #|.split-layout{--sidebar-size:320px;display:grid;grid-template-columns:minmax(180px,var(--sidebar-size)) 10px minmax(0,1fr);gap:0;align-items:stretch;height:calc(100vh - 100px);overflow:hidden;}
    #|.file-sidebar{height:100%;min-height:0;overflow-y:auto;padding-right:8px;}
    #|.split-resizer{position:relative;cursor:col-resize;touch-action:none;}
    #|.split-resizer::before{content:"";position:absolute;left:4px;top:0;bottom:0;width:2px;background:var(--border);}
    #|.split-resizer:hover::before,.split-resizer:focus-visible::before{background:var(--link);}
    #|.split-resizer:focus-visible{outline:none;background:var(--pre-bg);}
    #|body[data-resizing="1"]{cursor:col-resize;user-select:none;}
    #|.split-layout main{min-width:0;min-height:0;overflow:auto;padding-left:12px;border-left:1px solid var(--border);}
    #|a{color:var(--link);}
    #|a:visited{color:var(--link-visited);}
    #|#repo-file-tree{margin:0;padding-left:0;}
    #|nav ul[role=tree],nav ul[role=group]{list-style:none;}
    #|nav ul[role=group]{margin:0;padding-left:0;}
    #|nav li[role=treeitem]{list-style:none;margin:2px 0;}
    #|nav li[role=treeitem]::marker{content:"";}
    #|.file-tree-dir{margin:0;}
    #|.file-tree-summary,.file-tree-link{display:flex;align-items:center;gap:6px;padding:2px 4px;border-radius:4px;outline:none;}
    #|.file-tree-summary{cursor:pointer;font-weight:600;list-style:none;}
    #|.file-tree-summary::marker{content:"";}
    #|.file-tree-summary::-webkit-details-marker{display:none;}
    #|.file-tree-summary:focus-visible,.file-tree-link:focus-visible{outline:2px solid var(--link);outline-offset:2px;background:var(--pre-bg);}
    #|.file-tree-link{text-decoration:none;}
    #|.file-tree-toggle{display:inline-block;width:1em;color:var(--text);transform-origin:center;transition:transform .12s ease;}
    #|.file-tree-toggle-placeholder{visibility:hidden;}
    #|.file-tree-dir[open]>.file-tree-summary .file-tree-toggle{transform:rotate(90deg);}
    #|.file-tree-icon{display:inline-block;width:1.1em;text-align:center;line-height:1;}
    #|.file-tree-label{min-width:0;overflow-wrap:anywhere;}
    #|nav ul.file-tree-children{margin:3px 0 3px 6px;padding-left:4px;border-left:1px solid var(--tree-guide);}
    #|pre{background:var(--pre-bg);padding:12px;overflow:auto;}
    #|code{font-family:ui-monospace,Menlo,monospace;}
    #|@media (max-width: 900px){html,body{height:auto;}body{padding-top:68px;padding-bottom:12px;overflow:auto;}footer{position:static;padding:8px 0 0;border-top:none;font-size:inherit;}.split-layout{display:flex;flex-direction:column;gap:12px;height:auto;overflow:visible;}.split-resizer{display:none;}.split-layout main{order:1;overflow:visible;padding-left:0;border-left:none;}.file-sidebar{order:2;height:auto;overflow:visible;padding-right:0;border-right:none;border-top:1px solid var(--border);padding-top:8px;}}
  let head = "<meta charset=\"utf-8\"><style>" + css + "</style>"
  @sol.render_page(page, title="bithub", head~)
}

///|
fn normalize_route_base(route_base : String) -> String {
  let trimmed = route_base.trim(chars=" \n\r\t").to_string()
  if trimmed.length() == 0 || trimmed == "/" {
    return ""
  }
  let mut normalized = if trimmed.has_prefix("/") {
    trimmed
  } else {
    "/" + trimmed
  }
  while normalized.has_suffix("/") && normalized.length() > 1 {
    normalized = String::unsafe_substring(
      normalized,
      start=0,
      end=normalized.length() - 1,
    )
  }
  normalized
}

///|
fn route_root(route_base : String) -> String {
  if route_base.length() == 0 {
    "/"
  } else {
    route_base
  }
}

///|
fn route_issues(route_base : String) -> String {
  if route_base.length() == 0 {
    "/issues"
  } else {
    route_base + "/issues"
  }
}

///|
fn route_blob_prefix(route_base : String) -> String {
  if route_base.length() == 0 {
    "/blob"
  } else {
    route_base + "/blob"
  }
}

///|
fn tree_keyboard_script() -> String {
  let script =
    #|(() => {
    #|  const tree = document.querySelector('nav[aria-label="repository files"] ul[role="tree"]');
    #|  if (!(tree instanceof HTMLElement)) return;
    #|
    #|  const nodeSelector = 'summary.file-tree-summary[data-tree-node], a.file-tree-link[data-tree-node]';
    #|  const allNodes = () => Array.from(tree.querySelectorAll(nodeSelector)).filter((node) => node instanceof HTMLElement);
    #|
    #|  const syncAriaExpanded = (details) => {
    #|    const treeitem = details.closest('li[role="treeitem"]');
    #|    if (treeitem instanceof HTMLElement) {
    #|      treeitem.setAttribute('aria-expanded', details.open ? 'true' : 'false');
    #|    }
    #|  };
    #|
    #|  const isVisibleNode = (node) => {
    #|    let current = node.parentElement;
    #|    while (current && current !== tree) {
    #|      if (current.tagName === 'DETAILS') {
    #|        const ownSummary = node.tagName === 'SUMMARY' && node.parentElement === current;
    #|        if (!current.open && !ownSummary) {
    #|          return false;
    #|        }
    #|      }
    #|      current = current.parentElement;
    #|    }
    #|    return true;
    #|  };
    #|
    #|  const visibleNodes = () => allNodes().filter((node) => isVisibleNode(node));
    #|
    #|  const markTabStop = (target) => {
    #|    for (const node of allNodes()) {
    #|      node.tabIndex = node === target ? 0 : -1;
    #|    }
    #|  };
    #|
    #|  const focusNode = (target) => {
    #|    markTabStop(target);
    #|    target.focus();
    #|  };
    #|
    #|  const findParentSummary = (node) => {
    #|    const currentDetails = node.closest('details');
    #|    if (!(currentDetails instanceof HTMLElement)) return null;
    #|    const parentDetails = currentDetails.parentElement?.closest('details');
    #|    if (!(parentDetails instanceof HTMLElement)) return null;
    #|    const summary = parentDetails.querySelector(':scope > summary.file-tree-summary[data-tree-node]');
    #|    return summary instanceof HTMLElement ? summary : null;
    #|  };
    #|
    #|  for (const details of tree.querySelectorAll('details.file-tree-dir')) {
    #|    if (details instanceof HTMLDetailsElement) {
    #|      syncAriaExpanded(details);
    #|      details.addEventListener('toggle', () => syncAriaExpanded(details));
    #|    }
    #|  }
    #|
    #|  const initialNodes = visibleNodes();
    #|  const selected = tree.querySelector('li[role="treeitem"][aria-selected="true"] a.file-tree-link[data-tree-node]');
    #|  if (selected instanceof HTMLElement) {
    #|    markTabStop(selected);
    #|  } else if (initialNodes.length > 0) {
    #|    markTabStop(initialNodes[0]);
    #|  }
    #|
    #|  tree.addEventListener('focusin', (event) => {
    #|    const target = event.target;
    #|    if (!(target instanceof HTMLElement)) return;
    #|    const node = target.closest(nodeSelector);
    #|    if (node instanceof HTMLElement) {
    #|      markTabStop(node);
    #|    }
    #|  });
    #|
    #|  tree.addEventListener('keydown', (event) => {
    #|    const target = event.target;
    #|    if (!(target instanceof HTMLElement)) return;
    #|    const current = target.closest(nodeSelector);
    #|    if (!(current instanceof HTMLElement)) return;
    #|
    #|    const nodes = visibleNodes();
    #|    const index = nodes.indexOf(current);
    #|    if (index < 0) return;
    #|
    #|    if (event.key === 'ArrowDown') {
    #|      event.preventDefault();
    #|      if (index < nodes.length - 1) focusNode(nodes[index + 1]);
    #|      return;
    #|    }
    #|
    #|    if (event.key === 'ArrowUp') {
    #|      event.preventDefault();
    #|      if (index > 0) focusNode(nodes[index - 1]);
    #|      return;
    #|    }
    #|
    #|    if (event.key === 'Home') {
    #|      event.preventDefault();
    #|      if (nodes.length > 0) focusNode(nodes[0]);
    #|      return;
    #|    }
    #|
    #|    if (event.key === 'End') {
    #|      event.preventDefault();
    #|      if (nodes.length > 0) focusNode(nodes[nodes.length - 1]);
    #|      return;
    #|    }
    #|
    #|    if (event.key === 'ArrowRight' && current.tagName === 'SUMMARY') {
    #|      const details = current.parentElement;
    #|      if (details instanceof HTMLDetailsElement) {
    #|        if (!details.open) {
    #|          event.preventDefault();
    #|          details.open = true;
    #|          syncAriaExpanded(details);
    #|          return;
    #|        }
    #|        const firstChild = details.querySelector(
    #|          ':scope > ul[role="group"] summary.file-tree-summary[data-tree-node], :scope > ul[role="group"] a.file-tree-link[data-tree-node]',
    #|        );
    #|        if (firstChild instanceof HTMLElement) {
    #|          event.preventDefault();
    #|          focusNode(firstChild);
    #|        }
    #|      }
    #|      return;
    #|    }
    #|
    #|    if (event.key === 'ArrowLeft') {
    #|      if (current.tagName === 'SUMMARY') {
    #|        const details = current.parentElement;
    #|        if (details instanceof HTMLDetailsElement && details.open) {
    #|          event.preventDefault();
    #|          details.open = false;
    #|          syncAriaExpanded(details);
    #|          return;
    #|        }
    #|      }
    #|      const parentSummary = findParentSummary(current);
    #|      if (parentSummary) {
    #|        event.preventDefault();
    #|        focusNode(parentSummary);
    #|      }
    #|      return;
    #|    }
    #|
    #|    if (event.key === ' ' && current.tagName === 'A') {
    #|      event.preventDefault();
    #|      current.click();
    #|    }
    #|  });
    #|})();
  script
}

///|
fn split_resizer_script() -> String {
  let script =
    #|(() => {
    #|  const layout = document.querySelector('.split-layout');
    #|  const resizer = document.querySelector('.split-resizer');
    #|  const sidebar = document.querySelector('.file-sidebar');
    #|  if (!(layout instanceof HTMLElement)) return;
    #|  if (!(resizer instanceof HTMLElement)) return;
    #|  if (!(sidebar instanceof HTMLElement)) return;
    #|
    #|  const desktop = window.matchMedia('(min-width: 901px)');
    #|  const minSize = 180;
    #|  const maxSizeFallback = 720;
    #|  const keepMainMin = 260;
    #|
    #|  const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
    #|  const computeMax = () => {
    #|    const container = layout.getBoundingClientRect().width;
    #|    return Math.max(minSize, Math.min(maxSizeFallback, container - keepMainMin));
    #|  };
    #|
    #|  let current = Math.round(sidebar.getBoundingClientRect().width);
    #|
    #|  const apply = (next) => {
    #|    if (!desktop.matches) return;
    #|    current = clamp(next, minSize, computeMax());
    #|    layout.style.setProperty('--sidebar-size', current + 'px');
    #|    resizer.setAttribute('aria-valuemin', String(minSize));
    #|    resizer.setAttribute('aria-valuemax', String(computeMax()));
    #|    resizer.setAttribute('aria-valuenow', String(Math.round(current)));
    #|  };
    #|
    #|  const sync = () => {
    #|    const gridColumns = getComputedStyle(layout).gridTemplateColumns.trim().split(/\s+/);
    #|    const parsed = Number.parseFloat(gridColumns[0] ?? '');
    #|    if (Number.isFinite(parsed) && parsed > 0) {
    #|      current = parsed;
    #|    }
    #|    apply(current);
    #|  };
    #|
    #|  if (desktop.matches) {
    #|    sync();
    #|  }
    #|
    #|  let dragging = false;
    #|  let activePointer = -1;
    #|  let startX = 0;
    #|  let startSize = 0;
    #|
    #|  const stopDragging = () => {
    #|    dragging = false;
    #|    activePointer = -1;
    #|    document.body.removeAttribute('data-resizing');
    #|  };
    #|
    #|  resizer.addEventListener('pointerdown', (event) => {
    #|    if (!desktop.matches) return;
    #|    if (event.button !== 0) return;
    #|    dragging = true;
    #|    activePointer = event.pointerId;
    #|    startX = event.clientX;
    #|    startSize = sidebar.getBoundingClientRect().width;
    #|    document.body.setAttribute('data-resizing', '1');
    #|    resizer.setPointerCapture(event.pointerId);
    #|    event.preventDefault();
    #|  });
    #|
    #|  resizer.addEventListener('pointermove', (event) => {
    #|    if (!dragging || event.pointerId !== activePointer) return;
    #|    const delta = event.clientX - startX;
    #|    apply(startSize + delta);
    #|  });
    #|
    #|  resizer.addEventListener('pointerup', (event) => {
    #|    if (!dragging || event.pointerId !== activePointer) return;
    #|    try {
    #|      resizer.releasePointerCapture(event.pointerId);
    #|    } catch (_) {}
    #|    stopDragging();
    #|  });
    #|
    #|  resizer.addEventListener('pointercancel', (event) => {
    #|    if (!dragging || event.pointerId !== activePointer) return;
    #|    try {
    #|      resizer.releasePointerCapture(event.pointerId);
    #|    } catch (_) {}
    #|    stopDragging();
    #|  });
    #|
    #|  resizer.addEventListener('keydown', (event) => {
    #|    if (!desktop.matches) return;
    #|    const step = event.shiftKey ? 32 : 16;
    #|    if (event.key === 'ArrowLeft') {
    #|      event.preventDefault();
    #|      apply(current - step);
    #|      return;
    #|    }
    #|    if (event.key === 'ArrowRight') {
    #|      event.preventDefault();
    #|      apply(current + step);
    #|      return;
    #|    }
    #|    if (event.key === 'Home') {
    #|      event.preventDefault();
    #|      apply(minSize);
    #|      return;
    #|    }
    #|    if (event.key === 'End') {
    #|      event.preventDefault();
    #|      apply(computeMax());
    #|    }
    #|  });
    #|
    #|  window.addEventListener('resize', () => {
    #|    if (!desktop.matches) return;
    #|    apply(current);
    #|  });
    #|
    #|  desktop.addEventListener?.('change', () => {
    #|    stopDragging();
    #|    if (!desktop.matches) {
    #|      layout.style.removeProperty('--sidebar-size');
    #|      resizer.removeAttribute('aria-valuenow');
    #|      return;
    #|    }
    #|    sync();
    #|  });
    #|})();
  script
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
  blob_route_prefix : String,
) -> Array[@luna.Node[Unit, String]] {
  let limit = if files.length() < 120 { files.length() } else { 120 }
  let limited_files : Array[String] = []
  for i in 0..<limit {
    limited_files.push(files[i])
  }
  let tree_nodes = build_tree_nodes(
    limited_files, "", selected_path, blob_route_prefix,
  )
  if files.length() > limit {
    tree_nodes.push(
      @luna.h("li", [("role", @luna.attr_static("treeitem"))], [
        @luna.text("..."),
      ]),
    )
  }
  [
    @components.tree(
      id="repo-file-tree",
      aria_label="repository file tree",
      tree_nodes,
    ),
  ]
}

///|
fn build_tree_nodes(
  files : Array[String],
  prefix : String,
  selected_path : String,
  blob_route_prefix : String,
) -> Array[@luna.Node[Unit, String]] {
  let dir_names : Array[String] = []
  let file_entries : Array[(String, String)] = []

  for path in files {
    match classify_child_path(path, prefix) {
      Some((name, is_dir)) =>
        if is_dir {
          if !dir_names.contains(name) {
            dir_names.push(name)
          }
        } else {
          let file_path = if prefix.length() == 0 {
            name
          } else {
            prefix + "/" + name
          }
          file_entries.push((file_path, name))
        }
      None => ()
    }
  }

  dir_names.sort_by(fn(a, b) { String::compare(a, b) })
  file_entries.sort_by(fn(a, b) { String::compare(a.1, b.1) })

  let nodes : Array[@luna.Node[Unit, String]] = []
  for dir_name in dir_names {
    let dir_path = if prefix.length() == 0 {
      dir_name
    } else {
      prefix + "/" + dir_name
    }
    let is_open = is_tree_dir_open(dir_path, selected_path)
    let details_attrs : Array[(String, @luna.Attr[Unit, String])] = [
      ("class", @luna.attr_static("file-tree-dir")),
      ("data-tree-path", @luna.attr_static(dir_path)),
    ]
    if is_open {
      details_attrs.push(("open", @luna.attr_static("open")))
    }
    let children = build_tree_nodes(
      files, dir_path, selected_path, blob_route_prefix,
    )
    nodes.push(
      @luna.h(
        "li",
        [
          ("role", @luna.attr_static("treeitem")),
          ("aria-selected", @luna.attr_static("false")),
          (
            "aria-expanded",
            @luna.attr_static(if is_open { "true" } else { "false" }),
          ),
        ],
        [
          @luna.h("details", details_attrs, [
            @luna.h(
              "summary",
              [
                ("class", @luna.attr_static("file-tree-summary")),
                ("tabindex", @luna.attr_static("-1")),
                ("data-tree-node", @luna.attr_static("1")),
                ("data-tree-kind", @luna.attr_static("dir")),
                ("data-tree-path", @luna.attr_static(dir_path)),
              ],
              [
                @luna.h(
                  "span",
                  [
                    ("class", @luna.attr_static("file-tree-toggle")),
                    ("aria-hidden", @luna.attr_static("true")),
                  ],
                  [@luna.text("▸")],
                ),
                @luna.h(
                  "span",
                  [
                    (
                      "class",
                      @luna.attr_static("file-tree-icon file-tree-icon-dir"),
                    ),
                    ("aria-hidden", @luna.attr_static("true")),
                  ],
                  [@luna.text("📁")],
                ),
                @luna.h(
                  "span",
                  [("class", @luna.attr_static("file-tree-label"))],
                  [@luna.text(dir_name)],
                ),
              ],
            ),
            @luna.h(
              "ul",
              [
                ("role", @luna.attr_static("group")),
                ("class", @luna.attr_static("file-tree-children")),
              ],
              children,
            ),
          ]),
        ],
      ),
    )
  }

  for entry in file_entries {
    let file_path = entry.0
    let file_name = entry.1
    let is_selected = file_path == selected_path
    let label = if file_path == selected_path {
      "[*] " + file_name
    } else {
      file_name
    }
    let link_attrs : Array[(String, @luna.Attr[Unit, String])] = [
      ("href", @luna.attr_static(blob_route_prefix + "/" + file_path)),
      ("class", @luna.attr_static("file-tree-link")),
      ("tabindex", @luna.attr_static("-1")),
      ("data-tree-node", @luna.attr_static("1")),
      ("data-tree-kind", @luna.attr_static("file")),
      ("data-tree-path", @luna.attr_static(file_path)),
    ]
    if is_selected {
      link_attrs.push(("aria-current", @luna.attr_static("page")))
    }
    nodes.push(
      @luna.h(
        "li",
        [
          ("role", @luna.attr_static("treeitem")),
          (
            "aria-selected",
            @luna.attr_static(
              if file_path == selected_path {
                "true"
              } else {
                "false"
              },
            ),
          ),
        ],
        [
          @luna.h("a", link_attrs, [
            @luna.h(
              "span",
              [
                (
                  "class",
                  @luna.attr_static(
                    "file-tree-toggle file-tree-toggle-placeholder",
                  ),
                ),
                ("aria-hidden", @luna.attr_static("true")),
              ],
              [@luna.text("▸")],
            ),
            @luna.h(
              "span",
              [
                (
                  "class",
                  @luna.attr_static("file-tree-icon file-tree-icon-file"),
                ),
                ("aria-hidden", @luna.attr_static("true")),
              ],
              [@luna.text("📄")],
            ),
            @luna.h("span", [("class", @luna.attr_static("file-tree-label"))], [
              @luna.text(label),
            ]),
          ]),
        ],
      ),
    )
  }

  nodes
}

///|
fn classify_child_path(path : String, prefix : String) -> (String, Bool)? {
  if prefix.length() == 0 {
    let parts = path.split("/").collect()
    if parts.length() == 0 {
      return None
    }
    let name = parts[0].to_string()
    return Some((name, parts.length() > 1))
  }

  let base = prefix + "/"
  if !path.has_prefix(base) {
    return None
  }
  let rest = String::unsafe_substring(
    path,
    start=base.length(),
    end=path.length(),
  )
  let parts = rest.split("/").collect()
  if parts.length() == 0 {
    return None
  }
  let name = parts[0].to_string()
  Some((name, parts.length() > 1))
}

///|
fn is_tree_dir_open(dir_path : String, selected_path : String) -> Bool {
  selected_path == dir_path || selected_path.has_prefix(dir_path + "/")
}

///|
fn shorten_home_prefix(path : String) -> String {
  match @nprocess.env().get("HOME") {
    Some(home) => replace_path_prefix_with_tilde(path, home)
    None => path
  }
}

///|
pub fn replace_path_prefix_with_tilde(path : String, home : String) -> String {
  let home_prefix = if home.has_suffix("/") {
    String::unsafe_substring(home, start=0, end=home.length() - 1)
  } else {
    home
  }
  if home_prefix.length() == 0 {
    return path
  }
  if path == home_prefix {
    return "~"
  }
  let prefix = home_prefix + "/"
  if path.has_prefix(prefix) {
    let rel = String::unsafe_substring(
      path,
      start=prefix.length(),
      end=path.length(),
    )
    "~/" + rel
  } else {
    path
  }
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
