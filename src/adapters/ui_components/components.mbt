///| Semantic HTML primitives used by bithub's server-rendered views.
///|
/// The former `mizchi/luna/x/components` package is not present in the
/// current Luna release line. Keeping the small surface bithub needs here
/// decouples its public views from that removed package.

///|
pub fn[E] link(
  href : String,
  children : Array[@luna.Node[E, String]],
) -> @luna.Node[E, String] {
  @luna.h("a", [("href", @luna.attr_static(href))], children)
}

///|
pub fn[E] banner(
  children : Array[@luna.Node[E, String]],
) -> @luna.Node[E, String] {
  @luna.h("header", [], children)
}

///|
pub fn[E] nav(
  aria_label? : String,
  children : Array[@luna.Node[E, String]],
) -> @luna.Node[E, String] {
  let attrs : Array[(String, @luna.Attr[E, String])] = []
  if aria_label is Some(label) {
    attrs.push(("aria-label", @luna.attr_static(label)))
  }
  @luna.h("nav", attrs, children)
}

///|
pub fn[E] main_content(
  children : Array[@luna.Node[E, String]],
) -> @luna.Node[E, String] {
  @luna.h("main", [], children)
}

///|
pub fn[E] contentinfo(
  children : Array[@luna.Node[E, String]],
) -> @luna.Node[E, String] {
  @luna.h("footer", [], children)
}

///|
pub fn[E] region(
  aria_label? : String,
  children : Array[@luna.Node[E, String]],
) -> @luna.Node[E, String] {
  let attrs : Array[(String, @luna.Attr[E, String])] = []
  if aria_label is Some(label) {
    attrs.push(("aria-label", @luna.attr_static(label)))
  }
  @luna.h("section", attrs, children)
}

///|
pub fn[E] breadcrumb_from_path(
  base_path : String,
  segments : Array[(String, String)],
  current_label : String,
) -> @luna.Node[E, String] {
  let items : Array[@luna.Node[E, String]] = []
  let mut path = base_path
  for entry in segments {
    let (segment, label) = entry
    path = path + "/" + segment
    items.push(@luna.h("li", [], [link(path, [@luna.text(label)])]))
  }
  items.push(
    @luna.h(
      "li",
      [],
      [
        @luna.h(
          "a",
          [
            ("href", @luna.attr_static("#")),
            ("aria-current", @luna.attr_static("page")),
          ],
          [@luna.text(current_label)],
        ),
      ],
    ),
  )
  @luna.h(
    "nav",
    [("aria-label", @luna.attr_static("Breadcrumb"))],
    [@luna.h("ol", [], items)],
  )
}

///|
pub fn[E] tree(
  id? : String,
  aria_label? : String,
  tree_nodes : Array[@luna.Node[E, String]],
) -> @luna.Node[E, String] {
  let attrs : Array[(String, @luna.Attr[E, String])] = [
    ("role", @luna.attr_static("tree")),
  ]
  if id is Some(value) {
    attrs.push(("id", @luna.attr_static(value)))
  }
  if aria_label is Some(label) {
    attrs.push(("aria-label", @luna.attr_static(label)))
  }
  @luna.h("ul", attrs, tree_nodes)
}
