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
fn render_workflows_page(api : @core.ApiState) -> String {
  let workflows = api.list_workflows()
  let rows : Array[@luna.Node[Unit, String]] = []
  for wf in workflows {
    let trigger_text = wf.triggers.join(", ")
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [], [
          @components.link(
            "/actions/workflows/" + wf.filename,
            [@luna.text(wf.name)],
          ),
        ]),
        @luna.h("td", [], [@luna.text(wf.filename)]),
        @luna.h("td", [], [@luna.text(trigger_text)]),
        @luna.h("td", [], [@luna.text(wf.job_count.to_string())]),
      ]),
    )
  }
  if rows.length() == 0 {
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [("colspan", @luna.attr_static("4"))], [
          @luna.text("No workflows found"),
        ]),
      ]),
    )
  }
  let table = @luna.h("table", [("class", @luna.attr_static("wf-table"))], [
    @luna.h("thead", [], [
      @luna.h("tr", [], [
        @luna.h("th", [], [@luna.text("Name")]),
        @luna.h("th", [], [@luna.text("File")]),
        @luna.h("th", [], [@luna.text("Triggers")]),
        @luna.h("th", [], [@luna.text("Jobs")]),
      ]),
    ]),
    @luna.h("tbody", [], rows),
  ])
  render_layout("workflows", [
    @luna.h("h1", [], [@luna.text("Workflows")]),
    table,
  ])
}

///|
fn render_workflow_detail_page(
  api : @core.ApiState,
  filename : String,
) -> PageHtml {
  if filename.length() == 0 {
    return {
      status: 400,
      html: render_layout("workflow", [
        @luna.h("h1", [], [@luna.text("workflow")]),
        @luna.h("p", [], [@luna.text("usage: /actions/workflows/:file")]),
      ]),
    }
  }
  match api.workflow_detail(filename) {
    Some(detail) => {
      let content : Array[@luna.Node[Unit, String]] = [
        @luna.h("h1", [], [@luna.text(detail.name)]),
        @luna.h("p", [], [
          @luna.text("file: " + detail.filename + " | triggers: " + detail.triggers.join(
            ", ",
          )),
        ]),
      ]
      for job in detail.jobs {
        let step_nodes : Array[@luna.Node[Unit, String]] = []
        for step in job.steps {
          let desc = match step.uses {
            Some(uses) => "uses: " + uses
            None =>
              match step.run_preview {
                Some(r) => "run: " + r
                None => "(no action)"
              }
          }
          let label = if step.name.length() > 0 { step.name } else { step.id }
          step_nodes.push(
            @luna.h("li", [], [
              @luna.h("strong", [], [@luna.text(label)]),
              @luna.text(" — " + desc),
            ]),
          )
        }
        let runs_on_text = job.runs_on.join(", ")
        content.push(
          @luna.h("h2", [], [
            @luna.text("Job: " + job.name),
          ]),
        )
        content.push(
          @luna.h("p", [], [
            @luna.text(
              "runs-on: " + runs_on_text + " | steps: " + job.step_count.to_string(),
            ),
          ]),
        )
        content.push(@luna.h("ol", [], step_nodes))
      }
      { status: 200, html: render_layout(detail.name, content) }
    }
    None => {
      status: 404,
      html: render_layout(filename, [
        @luna.h("h1", [], [@luna.text(filename)]),
        @luna.h("p", [], [@luna.text("workflow not found")]),
      ]),
    }
  }
}


///|
fn render_tags_page(api : @core.ApiState) -> String {
  let tags = api.list_tags()
  let rows : Array[@luna.Node[Unit, String]] = []
  for tag in tags {
    let short_sha = if tag.sha.length() > 7 {
      String::unsafe_substring(tag.sha, start=0, end=7)
    } else {
      tag.sha
    }
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [], [@luna.h("strong", [], [@luna.text(tag.name)])]),
        @luna.h("td", [], [
          @components.link("/commit/" + tag.sha, [@luna.text(short_sha)]),
        ]),
        @luna.h("td", [], [@luna.text(tag.message)]),
      ]),
    )
  }
  if rows.length() == 0 {
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [("colspan", @luna.attr_static("3"))], [
          @luna.text("No tags"),
        ]),
      ]),
    )
  }
  let table = @luna.h("table", [("class", @luna.attr_static("wf-table"))], [
    @luna.h("thead", [], [
      @luna.h("tr", [], [
        @luna.h("th", [], [@luna.text("Tag")]),
        @luna.h("th", [], [@luna.text("SHA")]),
        @luna.h("th", [], [@luna.text("Message")]),
      ]),
    ]),
    @luna.h("tbody", [], rows),
  ])
  render_layout("Tags", [
    @luna.h("h1", [], [@luna.text("Tags")]),
    table,
  ])
}

///|
fn render_stats_page(api : @core.ApiState) -> String {
  let stats = api.repo_stats()
  let stat_items : Array[@luna.Node[Unit, String]] = [
    @luna.h("li", [], [
      @luna.text("Files: " + stats.file_count.to_string()),
    ]),
    @luna.h("li", [], [
      @luna.text("Commits: " + stats.commit_count.to_string()),
    ]),
    @luna.h("li", [], [
      @luna.text("Branches: " + stats.branch_count.to_string()),
    ]),
    @luna.h("li", [], [
      @luna.text("Issues: " + stats.issue_count.to_string()),
    ]),
    @luna.h("li", [], [
      @luna.text("Pull Requests: " + stats.pr_count.to_string()),
    ]),
  ]
  let content : Array[@luna.Node[Unit, String]] = [
    @luna.h("h1", [], [@luna.text("Repository Statistics")]),
    @luna.h("ul", [], stat_items),
  ]
  if stats.contributors.length() > 0 {
    content.push(
      @luna.h("h2", [], [@luna.text("Contributors")]),
    )
    let contrib_rows : Array[@luna.Node[Unit, String]] = []
    for entry in stats.contributors {
      contrib_rows.push(
        @luna.h("tr", [], [
          @luna.h("td", [], [@luna.text(entry.0)]),
          @luna.h("td", [], [
            @luna.text(entry.1.to_string() + " commits"),
          ]),
        ]),
      )
    }
    content.push(
      @luna.h("table", [("class", @luna.attr_static("wf-table"))], [
        @luna.h("thead", [], [
          @luna.h("tr", [], [
            @luna.h("th", [], [@luna.text("Author")]),
            @luna.h("th", [], [@luna.text("Commits")]),
          ]),
        ]),
        @luna.h("tbody", [], contrib_rows),
      ]),
    )
  }
  render_layout("Stats", content)
}

///|
fn render_blame_page(api : @core.ApiState, raw_path : String) -> PageHtml {
  if raw_path.length() == 0 {
    return {
      status: 400,
      html: render_layout("Blame", [
        @luna.h("h1", [], [@luna.text("Blame")]),
        @luna.h("p", [], [@luna.text("usage: /blame?path=file")]),
      ]),
    }
  }
  match api.blame(raw_path) {
    Some(lines) => {
      let rows : Array[@luna.Node[Unit, String]] = []
      for line in lines {
        let short_sha = if line.commit_sha.length() > 7 {
          String::unsafe_substring(line.commit_sha, start=0, end=7)
        } else {
          line.commit_sha
        }
        // Extract just the name from "name <email>" format
        let author_name = match line.author.find(" <") {
          Some(i) => String::unsafe_substring(line.author, start=0, end=i)
          None => line.author
        }
        rows.push(
          @luna.h("tr", [], [
            @luna.h(
              "td",
              [
                (
                  "style",
                  @luna.attr_static(
                    "text-align:right;padding-right:8px;user-select:none;opacity:0.5;",
                  ),
                ),
              ],
              [@luna.text(line.line_number.to_string())],
            ),
            @luna.h(
              "td",
              [
                (
                  "style",
                  @luna.attr_static(
                    "white-space:nowrap;padding-right:12px;font-size:12px;",
                  ),
                ),
              ],
              [
                @components.link(
                  "/commit/" + line.commit_sha,
                  [@luna.text(short_sha)],
                ),
              ],
            ),
            @luna.h(
              "td",
              [
                (
                  "style",
                  @luna.attr_static(
                    "white-space:nowrap;padding-right:12px;font-size:12px;opacity:0.7;",
                  ),
                ),
              ],
              [@luna.text(author_name)],
            ),
            @luna.h(
              "td",
              [
                (
                  "style",
                  @luna.attr_static(
                    "white-space:pre;font-family:ui-monospace,Menlo,monospace;font-size:13px;",
                  ),
                ),
              ],
              [@luna.text(line.content)],
            ),
          ]),
        )
      }
      let table = @luna.h(
        "table",
        [
          (
            "style",
            @luna.attr_static(
              "width:100%;border-collapse:collapse;font-size:13px;",
            ),
          ),
        ],
        [@luna.h("tbody", [], rows)],
      )
      {
        status: 200,
        html: render_layout("Blame: " + raw_path, [
          @luna.h("h1", [], [@luna.text("Blame: " + raw_path)]),
          @luna.h("p", [], [
            @components.link(
              "/file?path=" + raw_path,
              [@luna.text("view file")],
            ),
          ]),
          @luna.h(
            "div",
            [("style", @luna.attr_static("overflow-x:auto;"))],
            [table],
          ),
        ]),
      }
    }
    None => {
      status: 404,
      html: render_layout("Blame", [
        @luna.h("h1", [], [@luna.text("Blame: " + raw_path)]),
        @luna.h("p", [], [@luna.text("file not found")]),
      ]),
    }
  }
}

///|
fn render_webhooks_page(api : @core.ApiState) -> String {
  let webhooks = api.list_webhooks()
  let rows : Array[@luna.Node[Unit, String]] = []
  for wh in webhooks {
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [], [@luna.text(wh.id)]),
        @luna.h("td", [], [@luna.text(wh.event_type)]),
        @luna.h("td", [], [@luna.text(wh.source)]),
        @luna.h("td", [], [@luna.text(wh.triggered.to_string())]),
        @luna.h("td", [], [@luna.text(format_timestamp(wh.timestamp))]),
      ]),
    )
  }
  if rows.length() == 0 {
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [("colspan", @luna.attr_static("5"))], [
          @luna.text("No webhooks received"),
        ]),
      ]),
    )
  }
  let table = @luna.h("table", [("class", @luna.attr_static("wf-table"))], [
    @luna.h("thead", [], [
      @luna.h("tr", [], [
        @luna.h("th", [], [@luna.text("Event ID")]),
        @luna.h("th", [], [@luna.text("Type")]),
        @luna.h("th", [], [@luna.text("Source")]),
        @luna.h("th", [], [@luna.text("Triggered")]),
        @luna.h("th", [], [@luna.text("Time")]),
      ]),
    ]),
    @luna.h("tbody", [], rows),
  ])
  render_layout("Webhooks", [
    @luna.h("h1", [], [@luna.text("Webhook Log")]),
    table,
  ])
}

///|
fn render_pulls_page(api : @core.ApiState) -> String {
  let prs = api.list_pull_requests()
  let rows : Array[@luna.Node[Unit, String]] = []
  for pr in prs {
    let state_icon = match pr.state {
      "open" => "🟢"
      "merged" => "🟣"
      _ => "⚫"
    }
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [], [
          @components.link("/pulls/" + pr.id, [@luna.text("#" + pr.id)]),
        ]),
        @luna.h("td", [], [@luna.text(pr.title)]),
        @luna.h("td", [], [
          @luna.text(state_icon + " " + pr.state),
        ]),
        @luna.h("td", [], [
          @luna.text(pr.base_ref + " ← " + pr.head_ref),
        ]),
        @luna.h("td", [], [@luna.text(pr.author)]),
      ]),
    )
  }
  if rows.length() == 0 {
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [("colspan", @luna.attr_static("5"))], [
          @luna.text("No pull requests"),
        ]),
      ]),
    )
  }
  let table = @luna.h("table", [("class", @luna.attr_static("wf-table"))], [
    @luna.h("thead", [], [
      @luna.h("tr", [], [
        @luna.h("th", [], [@luna.text("ID")]),
        @luna.h("th", [], [@luna.text("Title")]),
        @luna.h("th", [], [@luna.text("State")]),
        @luna.h("th", [], [@luna.text("Refs")]),
        @luna.h("th", [], [@luna.text("Author")]),
      ]),
    ]),
    @luna.h("tbody", [], rows),
  ])
  render_layout("Pull Requests", [
    @luna.h("h1", [], [@luna.text("Pull Requests")]),
    table,
  ])
}

///|
fn render_pull_detail_page(
  api : @core.ApiState,
  id : String,
) -> PageHtml {
  match api.get_pull_request(id) {
    Some(detail) => {
      let content : Array[@luna.Node[Unit, String]] = [
        @luna.h("h1", [], [
          @luna.text("PR #" + id + " " + detail.pr.title),
        ]),
        @luna.h("p", [], [
          @luna.text(
            "state: " +
            detail.pr.state +
            " | author: " +
            detail.pr.author +
            " | " +
            detail.pr.base_ref +
            " ← " +
            detail.pr.head_ref,
          ),
        ]),
      ]
      if detail.body.length() > 0 {
        content.push(
          @components.region(
            aria_label="PR description",
            [@luna.raw_html(@markdown.md_to_html(detail.body))],
          ),
        )
      }
      match detail.compare {
        Some(cmp) => {
          content.push(
            @luna.h("p", [], [
              @luna.text(
                cmp.commits.length().to_string() +
                " commits, " +
                cmp.all_files.length().to_string() +
                " files changed",
              ),
            ]),
          )
          if cmp.all_files.length() > 0 {
            content.push(
              @luna.h("h2", [], [@luna.text("Files changed")]),
            )
            let file_nodes : Array[@luna.Node[Unit, String]] = []
            for df in cmp.all_files {
              file_nodes.push(
                @luna.h("li", [], [
                  @luna.h("strong", [], [@luna.text(df.path)]),
                  @luna.text(" [" + df.kind + "]"),
                ]),
              )
            }
            content.push(@luna.h("ul", [], file_nodes))
          }
        }
        None => ()
      }
      // PR reviews
      let reviews = api.list_pr_reviews(id)
      if reviews.length() > 0 {
        content.push(
          @luna.h("h2", [], [@luna.text("Reviews")]),
        )
        for review in reviews {
          let state_icon = match review.state {
            "approved" => "✅"
            "changes_requested" => "❌"
            _ => "💬"
          }
          let review_nodes : Array[@luna.Node[Unit, String]] = [
            @luna.h("p", [], [
              @luna.text(state_icon + " "),
              @luna.h("strong", [], [@luna.text(review.author)]),
              @luna.text(
                " " +
                review.state +
                " · " +
                format_timestamp(review.created_at),
              ),
            ]),
          ]
          if review.body.length() > 0 {
            review_nodes.push(
              @luna.raw_html(@markdown.md_to_html(review.body)),
            )
          }
          content.push(
            @luna.h(
              "div",
              [
                (
                  "style",
                  @luna.attr_static(
                    "border:1px solid var(--border);border-radius:6px;padding:12px;margin:8px 0;",
                  ),
                ),
              ],
              review_nodes,
            ),
          )
        }
      }
      // PR comments
      let comments = api.list_pr_comments(id)
      if comments.length() > 0 {
        content.push(
          @luna.h("h2", [], [
            @luna.text(
              "Comments (" + comments.length().to_string() + ")",
            ),
          ]),
        )
        for comment in comments {
          content.push(
            @luna.h(
              "div",
              [
                (
                  "style",
                  @luna.attr_static(
                    "border:1px solid var(--border);border-radius:6px;padding:12px;margin:8px 0;",
                  ),
                ),
              ],
              [
                @luna.h("p", [], [
                  @luna.h("strong", [], [@luna.text(comment.author)]),
                  @luna.text(" · " + format_timestamp(comment.created_at)),
                ]),
                @luna.raw_html(@markdown.md_to_html(comment.body)),
              ],
            ),
          )
        }
      }
      { status: 200, html: render_layout("PR #" + id, content) }
    }
    None => {
      status: 404,
      html: render_layout("Pull Request", [
        @luna.h("h1", [], [@luna.text("PR #" + id)]),
        @luna.h("p", [], [@luna.text("pull request not found")]),
      ]),
    }
  }
}

///|
fn render_search_page(api : @core.ApiState, query : String) -> String {
  let content : Array[@luna.Node[Unit, String]] = [
    @luna.h("h1", [], [@luna.text("Search")]),
    @luna.h(
      "form",
      [("method", @luna.attr_static("get")), ("action", @luna.attr_static("/search"))],
      [
        @luna.h(
          "input",
          [
            ("type", @luna.attr_static("text")),
            ("name", @luna.attr_static("q")),
            ("value", @luna.attr_static(query)),
            ("placeholder", @luna.attr_static("Search code...")),
            (
              "style",
              @luna.attr_static(
                "width:100%;max-width:500px;padding:8px;font-size:16px;",
              ),
            ),
          ],
          [],
        ),
      ],
    ),
  ]
  if query.length() > 0 {
    let results = api.search(query)
    content.push(
      @luna.h("p", [], [
        @luna.text(
          results.length().to_string() + " results for \"" + query + "\"",
        ),
      ]),
    )
    let result_nodes : Array[@luna.Node[Unit, String]] = []
    for r in results {
      result_nodes.push(
        @luna.h("li", [], [
          @components.link(
            "/file?path=" + r.path,
            [@luna.text(r.path + ":" + r.line_number.to_string())],
          ),
          @luna.h("pre", [("class", @luna.attr_static("source-code"))], [
            @luna.h("code", [], [@luna.text(r.line)]),
          ]),
        ]),
      )
    }
    if result_nodes.length() > 0 {
      content.push(@luna.h("ul", [], result_nodes))
    }
  }
  render_layout("Search", content)
}

///|
fn render_issues_page(api : @core.ApiState) -> String {
  let issues = api.list_issues()
  let rows : Array[@luna.Node[Unit, String]] = []
  for issue in issues {
    let state_label = if issue.state == "open" { "🟢" } else { "🟣" }
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [], [
          @components.link(
            "/issues/" + issue.id,
            [@luna.text("#" + issue.id)],
          ),
        ]),
        @luna.h("td", [], [@luna.text(issue.title)]),
        @luna.h("td", [], [@luna.text(state_label + " " + issue.state)]),
        @luna.h("td", [], [@luna.text(issue.author)]),
      ]),
    )
  }
  if rows.length() == 0 {
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [("colspan", @luna.attr_static("4"))], [
          @luna.text("No issues"),
        ]),
      ]),
    )
  }
  let table = @luna.h("table", [("class", @luna.attr_static("wf-table"))], [
    @luna.h("thead", [], [
      @luna.h("tr", [], [
        @luna.h("th", [], [@luna.text("ID")]),
        @luna.h("th", [], [@luna.text("Title")]),
        @luna.h("th", [], [@luna.text("State")]),
        @luna.h("th", [], [@luna.text("Author")]),
      ]),
    ]),
    @luna.h("tbody", [], rows),
  ])
  render_layout("Issues", [
    @luna.h("h1", [], [@luna.text("Issues")]),
    table,
  ])
}

///|
fn render_issue_detail_page(
  api : @core.ApiState,
  id : String,
) -> PageHtml {
  match api.get_issue(id) {
    Some(detail) => {
      let state_label = if detail.issue.state == "open" {
        "open"
      } else {
        "closed"
      }
      let content : Array[@luna.Node[Unit, String]] = [
        @luna.h("h1", [], [
          @luna.text("#" + detail.issue.id + " " + detail.issue.title),
        ]),
        @luna.h("p", [], [
          @luna.text(
            "state: " +
            state_label +
            " | author: " +
            detail.issue.author +
            " | created: " +
            format_timestamp(detail.issue.created_at),
          ),
        ]),
      ]
      // Show labels
      let labels = api.list_issue_labels(id)
      if labels.length() > 0 {
        let label_nodes : Array[@luna.Node[Unit, String]] = []
        for label in labels {
          label_nodes.push(
            @luna.h(
              "span",
              [
                (
                  "style",
                  @luna.attr_static(
                    "display:inline-block;padding:2px 8px;border-radius:12px;font-size:12px;font-weight:600;background:#" +
                    label.color +
                    ";color:#fff;margin-right:4px;",
                  ),
                ),
              ],
              [@luna.text(label.name)],
            ),
          )
        }
        content.push(@luna.h("p", [], label_nodes))
      }
      // Show milestone
      match api.get_issue_milestone(id) {
        Some(ms) =>
          content.push(
            @luna.h("p", [], [
              @luna.text("Milestone: "),
              @components.link(
                "/milestones/" + ms.id,
                [@luna.text(ms.title)],
              ),
            ]),
          )
        None => ()
      }
      if detail.issue.body.length() > 0 {
        content.push(
          @components.region(
            aria_label="issue body",
            [@luna.raw_html(@markdown.md_to_html(detail.issue.body))],
          ),
        )
      }
      if detail.comments.length() > 0 {
        content.push(
          @luna.h("h2", [], [
            @luna.text(
              "Comments (" + detail.comments.length().to_string() + ")",
            ),
          ]),
        )
        for comment in detail.comments {
          content.push(
            @luna.h(
              "div",
              [
                (
                  "style",
                  @luna.attr_static(
                    "border:1px solid var(--border);border-radius:6px;padding:12px;margin:8px 0;",
                  ),
                ),
              ],
              [
                @luna.h("p", [], [
                  @luna.h("strong", [], [@luna.text(comment.author)]),
                  @luna.text(" · " + format_timestamp(comment.created_at)),
                ]),
                @luna.raw_html(@markdown.md_to_html(comment.body)),
              ],
            ),
          )
        }
      }
      { status: 200, html: render_layout("#" + id + " " + detail.issue.title, content) }
    }
    None => {
      status: 404,
      html: render_layout("Issue", [
        @luna.h("h1", [], [@luna.text("Issue #" + id)]),
        @luna.h("p", [], [@luna.text("issue not found")]),
      ]),
    }
  }
}

///|
fn render_activity_page(api : @core.ApiState) -> String {
  let events = api.activity_feed()
  let items : Array[@luna.Node[Unit, String]] = []
  for event in events {
    let href = match event.kind {
      "commit" => "/commit/" + event.id
      "ci_run" => "/actions/runs/" + event.id
      "issue" => "/issues/" + event.id
      _ => "#"
    }
    items.push(
      @luna.h("tr", [], [
        @luna.h("td", [], [@luna.text(event.kind)]),
        @luna.h("td", [], [
          @components.link(href, [@luna.text(event.title)]),
        ]),
        @luna.h("td", [], [@luna.text(event.detail)]),
        @luna.h("td", [], [@luna.text(format_timestamp(event.timestamp))]),
      ]),
    )
  }
  if items.length() == 0 {
    items.push(
      @luna.h("tr", [], [
        @luna.h("td", [("colspan", @luna.attr_static("4"))], [
          @luna.text("No activity"),
        ]),
      ]),
    )
  }
  let table = @luna.h("table", [("class", @luna.attr_static("wf-table"))], [
    @luna.h("thead", [], [
      @luna.h("tr", [], [
        @luna.h("th", [], [@luna.text("Type")]),
        @luna.h("th", [], [@luna.text("Event")]),
        @luna.h("th", [], [@luna.text("Detail")]),
        @luna.h("th", [], [@luna.text("Time")]),
      ]),
    ]),
    @luna.h("tbody", [], items),
  ])
  render_layout("Activity", [
    @luna.h("h1", [], [@luna.text("Activity")]),
    table,
  ])
}

///|
fn render_compare_page(
  api : @core.ApiState,
  spec : String,
) -> PageHtml {
  // spec format: "base...head"
  let parts = match spec.find("...") {
    Some(i) => {
      let base = String::unsafe_substring(spec, start=0, end=i)
      let head = String::unsafe_substring(spec, start=i + 3, end=spec.length())
      Some((base, head))
    }
    None => None
  }
  match parts {
    None => {
      status: 400,
      html: render_layout("Compare", [
        @luna.h("h1", [], [@luna.text("Compare")]),
        @luna.h("p", [], [
          @luna.text("usage: /compare/base...head"),
        ]),
      ]),
    }
    Some((base, head)) =>
      match api.compare_commits(base, head) {
        Some(result) => {
          let content : Array[@luna.Node[Unit, String]] = [
            @luna.h("h1", [], [
              @luna.text("Compare: " + base + "..." + head),
            ]),
            @luna.h("p", [], [
              @luna.text(
                result.commits.length().to_string() +
                " commits, " +
                result.all_files.length().to_string() +
                " files changed",
              ),
            ]),
          ]
          // Commit list
          if result.commits.length() > 0 {
            content.push(
              @luna.h("h2", [], [@luna.text("Commits")]),
            )
            let commit_nodes : Array[@luna.Node[Unit, String]] = []
            for c in result.commits {
              let first_line = match c.message.find("\n") {
                Some(i) =>
                  String::unsafe_substring(c.message, start=0, end=i)
                None => c.message
              }
              commit_nodes.push(
                @luna.h("li", [], [
                  @components.link(
                    "/commit/" + c.sha,
                    [@luna.text(c.sha)],
                  ),
                  @luna.text(" " + first_line),
                ]),
              )
            }
            content.push(@luna.h("ul", [], commit_nodes))
          }
          // Changed files
          if result.all_files.length() > 0 {
            content.push(
              @luna.h("h2", [], [@luna.text("Files changed")]),
            )
            let file_nodes : Array[@luna.Node[Unit, String]] = []
            for df in result.all_files {
              file_nodes.push(
                @luna.h("li", [], [
                  @luna.h("strong", [], [@luna.text(df.path)]),
                  @luna.text(" [" + df.kind + "]"),
                  if df.patch.length() > 0 {
                    @luna.h(
                      "pre",
                      [("class", @luna.attr_static("source-code"))],
                      [@luna.h("code", [], [@luna.text(df.patch)])],
                    )
                  } else {
                    @luna.text("")
                  },
                ]),
              )
            }
            content.push(@luna.h("ul", [], file_nodes))
          }
          {
            status: 200,
            html: render_layout("Compare: " + base + "..." + head, content),
          }
        }
        None => {
          status: 404,
          html: render_layout("Compare", [
            @luna.h("h1", [], [
              @luna.text("Compare: " + base + "..." + head),
            ]),
            @luna.h("p", [], [@luna.text("no commits found between these refs")]),
          ]),
        }
      }
  }
}

///|
fn render_commits_page(api : @core.ApiState) -> String {
  let commits = api.list_commits()
  let rows : Array[@luna.Node[Unit, String]] = []
  for commit in commits {
    let short_sha = if commit.sha.length() > 7 {
      String::unsafe_substring(commit.sha, start=0, end=7)
    } else {
      commit.sha
    }
    let first_line = match commit.message.find("\n") {
      Some(i) => String::unsafe_substring(commit.message, start=0, end=i)
      None => commit.message
    }
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [], [
          @components.link("/commit/" + commit.sha, [@luna.text(short_sha)]),
        ]),
        @luna.h("td", [], [@luna.text(first_line)]),
        @luna.h("td", [], [@luna.text(commit.author)]),
        @luna.h("td", [], [@luna.text(format_timestamp(commit.timestamp))]),
      ]),
    )
  }
  if rows.length() == 0 {
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [("colspan", @luna.attr_static("4"))], [
          @luna.text("No commits"),
        ]),
      ]),
    )
  }
  let table = @luna.h("table", [("class", @luna.attr_static("wf-table"))], [
    @luna.h("thead", [], [
      @luna.h("tr", [], [
        @luna.h("th", [], [@luna.text("SHA")]),
        @luna.h("th", [], [@luna.text("Message")]),
        @luna.h("th", [], [@luna.text("Author")]),
        @luna.h("th", [], [@luna.text("Date")]),
      ]),
    ]),
    @luna.h("tbody", [], rows),
  ])
  render_layout("Commits", [
    @luna.h("h1", [], [@luna.text("Commits")]),
    table,
  ])
}

///|
fn render_commit_detail_page(
  api : @core.ApiState,
  sha : String,
) -> PageHtml {
  if sha.length() == 0 {
    return {
      status: 400,
      html: render_layout("Commit", [
        @luna.h("h1", [], [@luna.text("Commit")]),
        @luna.h("p", [], [@luna.text("usage: /commit/:sha")]),
      ]),
    }
  }
  match api.get_commit(sha) {
    Some(detail) => {
      let content : Array[@luna.Node[Unit, String]] = [
        @luna.h("h1", [], [
          @luna.text("Commit: " + sha),
        ]),
        @luna.h("p", [], [
          @luna.text(detail.commit.message),
        ]),
        @luna.h("p", [], [
          @luna.text(
            "author: " +
            detail.commit.author +
            " | date: " +
            format_timestamp(detail.commit.timestamp),
          ),
        ]),
      ]
      if detail.parent_sha.length() > 0 {
        content.push(
          @luna.h("p", [], [
            @luna.text("parent: "),
            @components.link(
              "/commit/" + detail.parent_sha,
              [@luna.text(detail.parent_sha)],
            ),
          ]),
        )
      }
      if detail.diff_files.length() > 0 {
        content.push(
          @luna.h("h2", [], [
            @luna.text(
              "Changed files (" + detail.diff_files.length().to_string() + ")",
            ),
          ]),
        )
        let diff_nodes : Array[@luna.Node[Unit, String]] = []
        for df in detail.diff_files {
          diff_nodes.push(
            @luna.h("li", [], [
              @luna.h("strong", [], [@luna.text(df.path)]),
              @luna.text(" [" + df.kind + "]"),
              render_diff_patch(df.patch),
            ]),
          )
        }
        content.push(@luna.h("ul", [], diff_nodes))
      }
      { status: 200, html: render_layout("Commit: " + sha, content) }
    }
    None => {
      status: 404,
      html: render_layout("Commit", [
        @luna.h("h1", [], [@luna.text("Commit: " + sha)]),
        @luna.h("p", [], [@luna.text("commit not found")]),
      ]),
    }
  }
}

///|
fn render_branches_page(api : @core.ApiState) -> String {
  let branches = api.list_branches()
  let rows : Array[@luna.Node[Unit, String]] = []
  for branch in branches {
    let short_sha = if branch.sha.length() > 7 {
      String::unsafe_substring(branch.sha, start=0, end=7)
    } else {
      branch.sha
    }
    let name_label = if branch.current {
      "* " + branch.name
    } else {
      branch.name
    }
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [], [@luna.text(name_label)]),
        @luna.h("td", [], [
          @components.link("/commit/" + branch.sha, [@luna.text(short_sha)]),
        ]),
      ]),
    )
  }
  if rows.length() == 0 {
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [("colspan", @luna.attr_static("2"))], [
          @luna.text("No branches"),
        ]),
      ]),
    )
  }
  let table = @luna.h("table", [("class", @luna.attr_static("wf-table"))], [
    @luna.h("thead", [], [
      @luna.h("tr", [], [
        @luna.h("th", [], [@luna.text("Branch")]),
        @luna.h("th", [], [@luna.text("SHA")]),
      ]),
    ]),
    @luna.h("tbody", [], rows),
  ])
  render_layout("Branches", [
    @luna.h("h1", [], [@luna.text("Branches")]),
    table,
  ])
}

///|
fn render_ci_page(api : @core.ApiState) -> String {
  let runs = api.list_ci_runs()
  let rows : Array[@luna.Node[Unit, String]] = []
  for run in runs {
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [], [
          @components.link(
            "/actions/runs/" + run.id,
            [@luna.text(run.id)],
          ),
        ]),
        @luna.h("td", [], [@luna.text(run.workflow_name)]),
        @luna.h("td", [], [@luna.text(run.ref_name)]),
        @luna.h("td", [], [@luna.text(run.status)]),
        @luna.h("td", [], [@luna.text(format_timestamp(run.triggered_at))]),
      ]),
    )
  }
  if rows.length() == 0 {
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [("colspan", @luna.attr_static("5"))], [
          @luna.text("No CI runs"),
        ]),
      ]),
    )
  }
  let table = @luna.h("table", [("class", @luna.attr_static("wf-table"))], [
    @luna.h("thead", [], [
      @luna.h("tr", [], [
        @luna.h("th", [], [@luna.text("ID")]),
        @luna.h("th", [], [@luna.text("Workflow")]),
        @luna.h("th", [], [@luna.text("Ref")]),
        @luna.h("th", [], [@luna.text("Status")]),
        @luna.h("th", [], [@luna.text("Triggered")]),
      ]),
    ]),
    @luna.h("tbody", [], rows),
  ])
  render_layout("CI Runs", [
    @luna.h("h1", [], [@luna.text("CI Runs")]),
    table,
  ])
}

///|
fn render_ci_run_detail_page(
  api : @core.ApiState,
  run_id : String,
) -> PageHtml {
  if run_id.length() == 0 {
    return {
      status: 400,
      html: render_layout("CI Run", [
        @luna.h("h1", [], [@luna.text("CI Run")]),
        @luna.h("p", [], [@luna.text("usage: /actions/runs/:id")]),
      ]),
    }
  }
  match api.get_ci_run_detail(run_id) {
    Some(detail) => {
      let status_label = detail.run.status
      let content : Array[@luna.Node[Unit, String]] = [
        @luna.h("h1", [], [
          @luna.text("CI Run: " + detail.run.workflow_name),
        ]),
        @luna.h("p", [], [
          @luna.text(
            "ref: " +
            detail.run.ref_name +
            " | status: " +
            status_label +
            " | triggered: " +
            format_timestamp(detail.run.triggered_at),
          ),
        ]),
      ]
      for job_detail in detail.jobs {
        let job = job_detail.job
        let step_nodes : Array[@luna.Node[Unit, String]] = []
        for step in job_detail.steps {
          let action = if step.uses.length() > 0 {
            "uses: " + step.uses
          } else if step.run_cmd.length() > 0 {
            "run: " + step.run_cmd
          } else {
            "(no action)"
          }
          step_nodes.push(
            @luna.h("li", [], [
              @luna.h("strong", [], [@luna.text(step.name)]),
              @luna.text(
                " [" + step.status + "] — " + action,
              ),
            ]),
          )
        }
        content.push(
          @luna.h("h2", [], [
            @luna.text("Job: " + job.name + " [" + job.status + "]"),
          ]),
        )
        content.push(@luna.h("ol", [], step_nodes))
      }
      { status: 200, html: render_layout("CI Run: " + run_id, content) }
    }
    None => {
      status: 404,
      html: render_layout("CI Run", [
        @luna.h("h1", [], [@luna.text("CI Run: " + run_id)]),
        @luna.h("p", [], [@luna.text("run not found")]),
      ]),
    }
  }
}

// ---- Releases Pages ----

///|
fn render_releases_page(api : @core.ApiState) -> String {
  let releases = api.list_releases()
  let rows : Array[@luna.Node[Unit, String]] = []
  for rel in releases {
    let badge = if rel.draft {
      "draft"
    } else if rel.prerelease {
      "pre-release"
    } else {
      "latest"
    }
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [], [
          @components.link(
            "/releases/" + rel.id,
            [@luna.text(rel.name)],
          ),
        ]),
        @luna.h("td", [], [@luna.text(rel.tag_name)]),
        @luna.h("td", [], [@luna.text(badge)]),
        @luna.h("td", [], [@luna.text(rel.author)]),
        @luna.h("td", [], [@luna.text(format_timestamp(rel.created_at))]),
      ]),
    )
  }
  if rows.length() == 0 {
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [("colspan", @luna.attr_static("5"))], [
          @luna.text("No releases"),
        ]),
      ]),
    )
  }
  let table = @luna.h("table", [("class", @luna.attr_static("wf-table"))], [
    @luna.h("thead", [], [
      @luna.h("tr", [], [
        @luna.h("th", [], [@luna.text("Release")]),
        @luna.h("th", [], [@luna.text("Tag")]),
        @luna.h("th", [], [@luna.text("Type")]),
        @luna.h("th", [], [@luna.text("Author")]),
        @luna.h("th", [], [@luna.text("Date")]),
      ]),
    ]),
    @luna.h("tbody", [], rows),
  ])
  render_layout("Releases", [
    @luna.h("h1", [], [@luna.text("Releases")]),
    table,
  ])
}

///|
fn render_release_detail_page(
  api : @core.ApiState,
  id : String,
) -> PageHtml {
  match api.get_release(id) {
    Some(rel) => {
      let badge = if rel.draft {
        "Draft"
      } else if rel.prerelease {
        "Pre-release"
      } else {
        "Latest"
      }
      let content : Array[@luna.Node[Unit, String]] = [
        @luna.h("h1", [], [@luna.text(rel.name)]),
        @luna.h("p", [], [
          @luna.text(
            "tag: " +
            rel.tag_name +
            " | " +
            badge +
            " | by " +
            rel.author +
            " | " +
            format_timestamp(rel.created_at),
          ),
        ]),
      ]
      if rel.body.length() > 0 {
        content.push(
          @components.region(
            aria_label="release notes",
            [@luna.raw_html(@markdown.md_to_html(rel.body))],
          ),
        )
      }
      { status: 200, html: render_layout(rel.name, content) }
    }
    None => {
      status: 404,
      html: render_layout("Release", [
        @luna.h("h1", [], [@luna.text("Release #" + id)]),
        @luna.h("p", [], [@luna.text("release not found")]),
      ]),
    }
  }
}

// ---- Labels Page ----

///|
fn render_labels_page(api : @core.ApiState) -> String {
  let labels = api.list_labels()
  let rows : Array[@luna.Node[Unit, String]] = []
  for label in labels {
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [], [
          @luna.h(
            "span",
            [
              (
                "style",
                @luna.attr_static(
                  "display:inline-block;padding:2px 8px;border-radius:12px;font-size:12px;font-weight:600;background:#" +
                  label.color +
                  ";color:#fff;",
                ),
              ),
            ],
            [@luna.text(label.name)],
          ),
        ]),
        @luna.h("td", [], [@luna.text("#" + label.color)]),
        @luna.h("td", [], [@luna.text(label.description)]),
      ]),
    )
  }
  if rows.length() == 0 {
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [("colspan", @luna.attr_static("3"))], [
          @luna.text("No labels"),
        ]),
      ]),
    )
  }
  let table = @luna.h("table", [("class", @luna.attr_static("wf-table"))], [
    @luna.h("thead", [], [
      @luna.h("tr", [], [
        @luna.h("th", [], [@luna.text("Label")]),
        @luna.h("th", [], [@luna.text("Color")]),
        @luna.h("th", [], [@luna.text("Description")]),
      ]),
    ]),
    @luna.h("tbody", [], rows),
  ])
  render_layout("Labels", [
    @luna.h("h1", [], [@luna.text("Labels")]),
    table,
  ])
}

// ---- Milestones Pages ----

///|
fn render_milestones_page(api : @core.ApiState) -> String {
  let milestones = api.list_milestones()
  let rows : Array[@luna.Node[Unit, String]] = []
  for ms in milestones {
    let state_icon = if ms.state == "open" { "🟢" } else { "🟣" }
    let due = if ms.due_date.length() > 0 {
      format_timestamp(ms.due_date)
    } else {
      "no due date"
    }
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [], [
          @components.link(
            "/milestones/" + ms.id,
            [@luna.text(ms.title)],
          ),
        ]),
        @luna.h("td", [], [@luna.text(state_icon + " " + ms.state)]),
        @luna.h("td", [], [@luna.text(due)]),
        @luna.h("td", [], [@luna.text(format_timestamp(ms.created_at))]),
      ]),
    )
  }
  if rows.length() == 0 {
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [("colspan", @luna.attr_static("4"))], [
          @luna.text("No milestones"),
        ]),
      ]),
    )
  }
  let table = @luna.h("table", [("class", @luna.attr_static("wf-table"))], [
    @luna.h("thead", [], [
      @luna.h("tr", [], [
        @luna.h("th", [], [@luna.text("Milestone")]),
        @luna.h("th", [], [@luna.text("State")]),
        @luna.h("th", [], [@luna.text("Due Date")]),
        @luna.h("th", [], [@luna.text("Created")]),
      ]),
    ]),
    @luna.h("tbody", [], rows),
  ])
  render_layout("Milestones", [
    @luna.h("h1", [], [@luna.text("Milestones")]),
    table,
  ])
}

///|
fn render_milestone_detail_page(
  api : @core.ApiState,
  id : String,
) -> PageHtml {
  match api.get_milestone(id) {
    Some(detail) => {
      let ms = detail.milestone
      let total = detail.open_issues + detail.closed_issues
      let progress = if total > 0 {
        (detail.closed_issues * 100 / total).to_string() + "%"
      } else {
        "0%"
      }
      let due = if ms.due_date.length() > 0 {
        format_timestamp(ms.due_date)
      } else {
        "no due date"
      }
      let content : Array[@luna.Node[Unit, String]] = [
        @luna.h("h1", [], [@luna.text(ms.title)]),
        @luna.h("p", [], [
          @luna.text(
            "state: " +
            ms.state +
            " | due: " +
            due +
            " | created: " +
            format_timestamp(ms.created_at),
          ),
        ]),
        @luna.h("p", [], [
          @luna.text(
            "Progress: " +
            progress +
            " (" +
            detail.closed_issues.to_string() +
            " closed, " +
            detail.open_issues.to_string() +
            " open)",
          ),
        ]),
      ]
      // Progress bar
      content.push(
        @luna.h(
          "div",
          [
            (
              "style",
              @luna.attr_static(
                "width:100%;height:10px;background:var(--border);border-radius:5px;overflow:hidden;margin:8px 0;",
              ),
            ),
          ],
          [
            @luna.h(
              "div",
              [
                (
                  "style",
                  @luna.attr_static(
                    "width:" + progress + ";height:100%;background:#3fb950;",
                  ),
                ),
              ],
              [],
            ),
          ],
        ),
      )
      if ms.description.length() > 0 {
        content.push(
          @components.region(
            aria_label="milestone description",
            [@luna.raw_html(@markdown.md_to_html(ms.description))],
          ),
        )
      }
      { status: 200, html: render_layout(ms.title, content) }
    }
    None => {
      status: 404,
      html: render_layout("Milestone", [
        @luna.h("h1", [], [@luna.text("Milestone #" + id)]),
        @luna.h("p", [], [@luna.text("milestone not found")]),
      ]),
    }
  }
}

// ---- Activity Graph Page ----

///|
fn render_activity_graph_page(api : @core.ApiState) -> String {
  let activity = api.commit_activity()
  let weekday_dist = api.commit_weekday_distribution()
  let hour_dist = api.commit_hour_distribution()
  let commits = api.list_commits()
  // Build date→count map for heatmap lookup
  let date_counts : Map[String, Int] = {}
  let mut max_count = 0
  for entry in activity {
    date_counts.set(entry.date, entry.count)
    if entry.count > max_count {
      max_count = entry.count
    }
  }
  // Generate SVG heatmap (52 weeks × 7 days, GitHub-style)
  // We render the most recent 52 weeks ending today-ish.
  // Use the latest commit date as reference if available, otherwise show empty.
  let ref_date = if commits.length() > 0 {
    commits[0].timestamp
  } else {
    ""
  }
  let svg = build_heatmap_svg(date_counts, max_count, ref_date)
  // Weekday bar chart
  let weekday_names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  let mut wd_max = 1
  for v in weekday_dist {
    if v > wd_max {
      wd_max = v
    }
  }
  let wd_bars : Array[@luna.Node[Unit, String]] = []
  for i = 0; i < 7; i = i + 1 {
    let pct = weekday_dist[i] * 100 / wd_max
    wd_bars.push(
      @luna.h(
        "div",
        [
          (
            "style",
            @luna.attr_static(
              "display:flex;align-items:center;gap:8px;margin:2px 0;",
            ),
          ),
        ],
        [
          @luna.h(
            "span",
            [
              (
                "style",
                @luna.attr_static("width:30px;font-size:12px;text-align:right;"),
              ),
            ],
            [@luna.text(weekday_names[i])],
          ),
          @luna.h(
            "div",
            [
              (
                "style",
                @luna.attr_static(
                  "height:14px;background:#3fb950;border-radius:2px;width:" +
                  pct.to_string() +
                  "%;min-width:2px;",
                ),
              ),
            ],
            [],
          ),
          @luna.h(
            "span",
            [("style", @luna.attr_static("font-size:12px;color:var(--text);"))],
            [@luna.text(weekday_dist[i].to_string())],
          ),
        ],
      ),
    )
  }
  // Hour bar chart
  let mut hr_max = 1
  for v in hour_dist {
    if v > hr_max {
      hr_max = v
    }
  }
  let hr_bars : Array[@luna.Node[Unit, String]] = []
  for i = 0; i < 24; i = i + 1 {
    let pct = hour_dist[i] * 100 / hr_max
    let label = if i < 10 {
      "0" + i.to_string()
    } else {
      i.to_string()
    }
    hr_bars.push(
      @luna.h(
        "div",
        [
          (
            "style",
            @luna.attr_static(
              "display:flex;align-items:center;gap:8px;margin:1px 0;",
            ),
          ),
        ],
        [
          @luna.h(
            "span",
            [
              (
                "style",
                @luna.attr_static(
                  "width:24px;font-size:11px;text-align:right;font-family:monospace;",
                ),
              ),
            ],
            [@luna.text(label)],
          ),
          @luna.h(
            "div",
            [
              (
                "style",
                @luna.attr_static(
                  "height:12px;background:#1f6feb;border-radius:2px;width:" +
                  pct.to_string() +
                  "%;min-width:1px;",
                ),
              ),
            ],
            [],
          ),
          @luna.h(
            "span",
            [("style", @luna.attr_static("font-size:11px;color:var(--text);"))],
            [@luna.text(if hour_dist[i] > 0 { hour_dist[i].to_string() } else { "" })],
          ),
        ],
      ),
    )
  }
  let total_commits = commits.length()
  let total_days = activity.length()
  let content : Array[@luna.Node[Unit, String]] = [
    @luna.h("h1", [], [@luna.text("Activity Graph")]),
    @luna.h("p", [], [
      @luna.text(
        total_commits.to_string() +
        " commits across " +
        total_days.to_string() +
        " active days",
      ),
    ]),
    @luna.h("h2", [], [@luna.text("Contribution Heatmap")]),
    @luna.h(
      "div",
      [("style", @luna.attr_static("overflow-x:auto;padding:8px 0;"))],
      [@luna.raw_html(svg)],
    ),
    @luna.h(
      "div",
      [
        (
          "style",
          @luna.attr_static(
            "display:flex;gap:32px;flex-wrap:wrap;margin-top:24px;",
          ),
        ),
      ],
      [
        @luna.h(
          "div",
          [("style", @luna.attr_static("flex:1;min-width:200px;"))],
          [
            @luna.h("h2", [], [@luna.text("Commits by Day of Week")]),
            @luna.h("div", [], wd_bars),
          ],
        ),
        @luna.h(
          "div",
          [("style", @luna.attr_static("flex:1;min-width:200px;"))],
          [
            @luna.h("h2", [], [@luna.text("Commits by Hour (UTC)")]),
            @luna.h("div", [], hr_bars),
          ],
        ),
      ],
    ),
  ]
  render_layout("Activity Graph", content)
}

///|
fn build_heatmap_svg(
  date_counts : Map[String, Int],
  max_count : Int,
  ref_timestamp : String,
) -> String {
  // Parse reference epoch to find the end date
  let mut ref_epoch = 0L
  for c in ref_timestamp {
    if c >= '0' && c <= '9' {
      ref_epoch = ref_epoch * 10L + (c.to_int() - '0'.to_int()).to_int64()
    }
  }
  if ref_epoch == 0L {
    return "<p>No commit data available for heatmap.</p>"
  }
  let secs_per_day = 86400L
  // End at end of reference day's week (Saturday)
  let ref_weekday = ((ref_epoch / secs_per_day + 4L) % 7L).to_int()
  // Days until Saturday
  let days_to_sat = (6 - ref_weekday).to_int64()
  let end_epoch = (ref_epoch / secs_per_day + days_to_sat) * secs_per_day
  // Go back 52 weeks (364 days) to start on a Sunday
  let start_epoch = end_epoch - 363L * secs_per_day
  let cell_size = 13
  let cell_gap = 3
  let left_pad = 32
  let top_pad = 20
  let total_weeks = 52
  let width = left_pad + total_weeks * (cell_size + cell_gap) + 10
  let height = top_pad + 7 * (cell_size + cell_gap) + 10
  let sb = StringBuilder::new()
  sb.write_string(
    "<svg width=\"" +
    width.to_string() +
    "\" height=\"" +
    height.to_string() +
    "\" xmlns=\"http://www.w3.org/2000/svg\">",
  )
  // Month labels
  let month_names = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct",
    "Nov", "Dec",
  ]
  let mut last_month = -1
  for week = 0; week < total_weeks; week = week + 1 {
    let day_epoch = start_epoch + (week * 7).to_int64() * secs_per_day
    let date_str = epoch_to_date_from_epoch(day_epoch)
    let month = parse_month_from_date(date_str)
    if month != last_month && month >= 0 {
      let x = left_pad + week * (cell_size + cell_gap)
      sb.write_string(
        "<text x=\"" +
        x.to_string() +
        "\" y=\"12\" font-size=\"10\" fill=\"currentColor\">" +
        month_names[month] +
        "</text>",
      )
      last_month = month
    }
  }
  // Day labels (Mon, Wed, Fri)
  let day_labels = ["", "Mon", "", "Wed", "", "Fri", ""]
  for d = 0; d < 7; d = d + 1 {
    if day_labels[d].length() > 0 {
      let y = top_pad + d * (cell_size + cell_gap) + 10
      sb.write_string(
        "<text x=\"0\" y=\"" +
        y.to_string() +
        "\" font-size=\"10\" fill=\"currentColor\">" +
        day_labels[d] +
        "</text>",
      )
    }
  }
  // Cells
  for week = 0; week < total_weeks; week = week + 1 {
    for day = 0; day < 7; day = day + 1 {
      let day_offset = (week * 7 + day).to_int64()
      let day_epoch = start_epoch + day_offset * secs_per_day
      let date_str = epoch_to_date_from_epoch(day_epoch)
      let count = date_counts.get(date_str).unwrap_or(0)
      let color = heatmap_color(count, max_count)
      let x = left_pad + week * (cell_size + cell_gap)
      let y = top_pad + day * (cell_size + cell_gap)
      sb.write_string(
        "<rect x=\"" +
        x.to_string() +
        "\" y=\"" +
        y.to_string() +
        "\" width=\"" +
        cell_size.to_string() +
        "\" height=\"" +
        cell_size.to_string() +
        "\" rx=\"2\" fill=\"" +
        color +
        "\"><title>" +
        date_str +
        ": " +
        count.to_string() +
        " commits</title></rect>",
      )
    }
  }
  // Legend
  let legend_x = left_pad
  let legend_y = height - 4
  sb.write_string(
    "<text x=\"" +
    legend_x.to_string() +
    "\" y=\"" +
    legend_y.to_string() +
    "\" font-size=\"10\" fill=\"currentColor\">Less</text>",
  )
  let legend_colors = ["#161b22", "#0e4429", "#006d32", "#26a641", "#39d353"]
  for i = 0; i < legend_colors.length(); i = i + 1 {
    let lx = legend_x + 30 + i * (cell_size + 2)
    let ly = legend_y - 10
    sb.write_string(
      "<rect x=\"" +
      lx.to_string() +
      "\" y=\"" +
      ly.to_string() +
      "\" width=\"" +
      cell_size.to_string() +
      "\" height=\"" +
      cell_size.to_string() +
      "\" rx=\"2\" fill=\"" +
      legend_colors[i] +
      "\"/>",
    )
  }
  let more_x = legend_x + 30 + legend_colors.length() * (cell_size + 2) + 4
  sb.write_string(
    "<text x=\"" +
    more_x.to_string() +
    "\" y=\"" +
    legend_y.to_string() +
    "\" font-size=\"10\" fill=\"currentColor\">More</text>",
  )
  sb.write_string("</svg>")
  sb.to_string()
}

///|
fn epoch_to_date_from_epoch(epoch : Int64) -> String {
  let secs_per_day = 86400L
  let mut days = epoch / secs_per_day
  let mut year = 1970L
  while true {
    let is_leap = (year % 4L == 0L && year % 100L != 0L) || year % 400L == 0L
    let year_days = if is_leap { 366L } else { 365L }
    if days < year_days {
      break
    }
    days -= year_days
    year += 1L
  }
  let is_leap = (year % 4L == 0L && year % 100L != 0L) || year % 400L == 0L
  let month_days = [
    31L, if is_leap { 29L } else { 28L }, 31L, 30L, 31L, 30L, 31L, 31L, 30L,
    31L, 30L, 31L,
  ]
  let mut month = 1L
  for md in month_days {
    if days < md {
      break
    }
    days -= md
    month += 1L
  }
  let day = days + 1L
  let pad2 = fn(n : Int64) -> String {
    if n < 10L { "0" + n.to_string() } else { n.to_string() }
  }
  year.to_string() + "-" + pad2(month) + "-" + pad2(day)
}

///|
fn parse_month_from_date(date : String) -> Int {
  // "YYYY-MM-DD" → month as 0-based index
  if date.length() < 7 {
    return -1
  }
  let m1 = date.unsafe_get(5)
  let m2 = date.unsafe_get(6)
  let month = (m1.to_int() - '0'.to_int()) * 10 + (m2.to_int() - '0'.to_int())
  month - 1 // 0-based
}

///|
fn heatmap_color(count : Int, max_count : Int) -> String {
  if count == 0 {
    return "#161b22"
  }
  if max_count <= 0 {
    return "#161b22"
  }
  let ratio = count * 4 / max_count
  match ratio {
    0 => "#0e4429"
    1 => "#006d32"
    2 => "#26a641"
    _ => "#39d353"
  }
}

// ---- Notifications Page ----

///|
fn render_notifications_page(api : @core.ApiState) -> String {
  let notifications = api.list_notifications()
  let unread = api.unread_notification_count()
  let rows : Array[@luna.Node[Unit, String]] = []
  for n in notifications {
    let kind_icon = match n.kind {
      "issue" => "🔴"
      "pr" => "🟣"
      "review" => "👀"
      "ci" => "⚙️"
      "release" => "🏷️"
      _ => "📌"
    }
    let read_style = if n.read {
      "opacity:0.6;"
    } else {
      "font-weight:600;"
    }
    rows.push(
      @luna.h(
        "tr",
        [("style", @luna.attr_static(read_style))],
        [
          @luna.h("td", [], [@luna.text(kind_icon)]),
          @luna.h("td", [], [
            if n.target_url.length() > 0 {
              @components.link(n.target_url, [@luna.text(n.title)])
            } else {
              @luna.text(n.title)
            },
          ]),
          @luna.h("td", [], [@luna.text(n.actor)]),
          @luna.h("td", [], [
            @luna.text(format_timestamp(n.created_at)),
          ]),
          @luna.h("td", [], [
            @luna.text(if n.read { "read" } else { "unread" }),
          ]),
        ],
      ),
    )
  }
  if rows.length() == 0 {
    rows.push(
      @luna.h("tr", [], [
        @luna.h("td", [("colspan", @luna.attr_static("5"))], [
          @luna.text("No notifications"),
        ]),
      ]),
    )
  }
  let table = @luna.h("table", [("class", @luna.attr_static("wf-table"))], [
    @luna.h("thead", [], [
      @luna.h("tr", [], [
        @luna.h("th", [], [@luna.text("")]),
        @luna.h("th", [], [@luna.text("Notification")]),
        @luna.h("th", [], [@luna.text("Actor")]),
        @luna.h("th", [], [@luna.text("Time")]),
        @luna.h("th", [], [@luna.text("Status")]),
      ]),
    ]),
    @luna.h("tbody", [], rows),
  ])
  let header_text = if unread > 0 {
    "Notifications (" + unread.to_string() + " unread)"
  } else {
    "Notifications"
  }
  render_layout("Notifications", [
    @luna.h("h1", [], [@luna.text(header_text)]),
    table,
  ])
}

