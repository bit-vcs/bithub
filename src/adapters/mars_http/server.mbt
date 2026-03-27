///|
extern "js" fn now_epoch_string() -> String =
  #| () => String(Math.floor(Date.now() / 1000))

///|
fn timestamp_or_now(raw : String) -> String {
  if raw.length() > 0 { raw } else { now_epoch_string() }
}

///|
fn get_spawn_config(ctx : @mars.Context) -> @core.CiSpawnConfig? {
  let url = ctx.env_var("CI_ORCHESTRATOR_URL").unwrap_or("")
  if url.length() == 0 {
    return None
  }
  Some({
    orchestrator_url: url,
    auth_token: ctx.env_var("CI_ORCHESTRATOR_TOKEN").unwrap_or(""),
    bithub_url: ctx.env_var("BITHUB_PUBLIC_URL").unwrap_or(""),
    bithub_token: ctx.env_var("CI_BITHUB_TOKEN").unwrap_or("tok-write-001"),
    container_image: ctx.env_var("CI_CONTAINER_IMAGE").unwrap_or(
      "bithub-ci-runner:latest",
    ),
  })
}

///|
fn require_write(
  api : @core.ApiState,
  ctx : @mars.Context,
) -> @core.TokenInfo? {
  let auth = api.authenticate(ctx.header("Authorization"))
  match auth {
    Authenticated(info) =>
      if info.role.can_write() {
        Some(info)
      } else {
        let e : Map[String, Json] = {}
        e.set("error", "forbidden: write permission required".to_json())
        ctx.json(e.to_json(), status=403)
        None
      }
    InvalidToken => {
      let e : Map[String, Json] = {}
      e.set("error", "unauthorized: invalid token".to_json())
      ctx.json(e.to_json(), status=401)
      None
    }
    Anonymous => {
      let e : Map[String, Json] = {}
      e.set("error", "unauthorized: Bearer token required".to_json())
      ctx.json(e.to_json(), status=401)
      None
    }
  }
}

///|
pub fn create_app() -> @mars.Server {
  create_app_with_storage(@core.ApiState::new())
}

///|
pub fn create_app_from_repo(root : String) -> @mars.Server {
  create_app_with_storage(@core.ApiState::from_repo(root))
}

///|
pub fn create_app_with_storage(api : @core.ApiState) -> @mars.Server {
  let app = @mars.Server::new()
  app.post(
    "/api/webhook/relay",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      let json_opt = ctx.body_json()
      match json_opt {
        Some(json) => {
          let runs = api.process_relay_webhook(json)
          // Auto-spawn CI containers if orchestrator is configured
          let spawn_config = get_spawn_config(ctx)
          match spawn_config {
            Some(config) =>
              for run in runs {
                let requests = api.build_spawn_requests(run.id)
                for req in requests {
                  @core.fire_spawn_request(config, req) |> ignore
                }
              }
            None => ()
          }
          // Log webhook
          let event_id = extract_json_string(json, "event_id")
          let event_type = extract_json_string(json, "event_type")
          let source = extract_json_string(json, "source")
          api.log_webhook(
            event_id,
            event_type,
            source,
            now_epoch_string(),
            runs.length(),
          )
          let resp : Map[String, Json] = {}
          resp.set("triggered", runs.length().to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let err : Map[String, Json] = {}
          err.set("error", "invalid json".to_json())
          ctx.json(err.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/actions/runs/status",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      let json_opt = ctx.body_json()
      match json_opt {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let run_id = match obj.get("run_id") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing run_id".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let job_id = match obj.get("job_id") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing job_id".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let step_index = match obj.get("step_index") {
            Some(Number(n, ..)) => n.to_int()
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing step_index".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let status = match obj.get("status") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing status".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let timestamp = timestamp_or_now(
            match obj.get("timestamp") {
              Some(String(s)) => s
              _ => ""
            },
          )
          let ok = api.update_step_status(
            run_id, job_id, step_index, status, timestamp,
          )
          let resp : Map[String, Json] = {}
          resp.set("ok", ok.to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/issues",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(token_info) else { return }
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let title = match obj.get("title") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing title".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let body = match obj.get("body") {
            Some(String(s)) => s
            _ => ""
          }
          let author = match obj.get("author") {
            Some(String(s)) => s
            _ => token_info.identity
          }
          let timestamp = timestamp_or_now(
            match obj.get("timestamp") {
              Some(String(s)) => s
              _ => ""
            },
          )
          let id = api.create_issue(title, body, author, timestamp)
          let resp : Map[String, Json] = {}
          resp.set("id", id.to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/issues/:id/comments",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(token_info) else { return }
      let issue_id = ctx.param("id").unwrap_or("")
      if issue_id.length() == 0 {
        let e : Map[String, Json] = {}
        e.set("error", "missing issue id".to_json())
        return ctx.json(e.to_json(), status=400)
      }
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let body = match obj.get("body") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing body".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let author = match obj.get("author") {
            Some(String(s)) => s
            _ => token_info.identity
          }
          let timestamp = timestamp_or_now(
            match obj.get("timestamp") {
              Some(String(s)) => s
              _ => ""
            },
          )
          let ok = api.add_comment(issue_id, author, body, timestamp)
          let resp : Map[String, Json] = {}
          resp.set("ok", ok.to_json())
          if not(ok) {
            resp.set("error", "issue not found".to_json())
          }
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/files",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(token_info) else { return }
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let path = match obj.get("path") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing path".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let content = match obj.get("content") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing content".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let message = match obj.get("message") {
            Some(String(s)) => s
            _ => "Edit " + path
          }
          let author = match obj.get("author") {
            Some(String(s)) => s
            _ => token_info.identity
          }
          let timestamp = timestamp_or_now(
            match obj.get("timestamp") {
              Some(String(s)) => s
              _ => ""
            },
          )
          let result = api.edit_file(path, content, message, author, timestamp)
          let resp : Map[String, Json] = {}
          resp.set("ok", result.ok.to_json())
          if result.ok {
            resp.set("commit_sha", result.commit_sha.to_json())
          } else {
            resp.set("error", result.error.to_json())
          }
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/pulls/:id/comments",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(token_info) else { return }
      let pr_id = ctx.param("id").unwrap_or("")
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let body = match obj.get("body") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing body".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let author = match obj.get("author") {
            Some(String(s)) => s
            _ => token_info.identity
          }
          let timestamp = timestamp_or_now(
            match obj.get("timestamp") {
              Some(String(s)) => s
              _ => ""
            },
          )
          let ok = api.add_pr_comment(pr_id, author, body, timestamp)
          let resp : Map[String, Json] = {}
          resp.set("ok", ok.to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/issues/:id/state",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      let issue_id = ctx.param("id").unwrap_or("")
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let state = match obj.get("state") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing state (open/closed)".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let ok = api.update_issue_state(issue_id, state)
          let resp : Map[String, Json] = {}
          resp.set("ok", ok.to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/pulls",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(token_info) else { return }
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let title = match obj.get("title") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing title".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let body = match obj.get("body") {
            Some(String(s)) => s
            _ => ""
          }
          let base_ref = match obj.get("base") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing base".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let head_ref = match obj.get("head") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing head".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let author = match obj.get("author") {
            Some(String(s)) => s
            _ => token_info.identity
          }
          let timestamp = timestamp_or_now(
            match obj.get("timestamp") {
              Some(String(s)) => s
              _ => ""
            },
          )
          let id = api.create_pull_request(
            title, body, author, base_ref, head_ref, timestamp,
          )
          let resp : Map[String, Json] = {}
          resp.set("id", id.to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/pulls/:id/merge",
    @mars.handler(fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      let pr_id = ctx.param("id").unwrap_or("")
      let ok = api.merge_pull_request(pr_id)
      let resp : Map[String, Json] = {}
      resp.set("ok", ok.to_json())
      ctx.json(resp.to_json())
    }),
  )
  app.post(
    "/api/pulls/:id/close",
    @mars.handler(fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      let pr_id = ctx.param("id").unwrap_or("")
      let ok = api.close_pull_request(pr_id)
      let resp : Map[String, Json] = {}
      resp.set("ok", ok.to_json())
      ctx.json(resp.to_json())
    }),
  )
  app.post(
    "/api/trigger",
    @mars.handler(fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      let runs = api.process_relay_webhook({
        "event_type": "relay.incoming_ref",
        "event_id": "local-" + @core.simple_hash(now_epoch_string()),
        "ref": "refs/relay/incoming/main",
        "source": "local-trigger",
        "occurred_at": 0,
        "room": "main",
        "target": "session:local",
      })
      let resp : Map[String, Json] = {}
      resp.set("triggered", runs.length().to_json())
      ctx.json(resp.to_json())
    }),
  )
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
      if route == "/commits" {
        return ctx.html(render_commits_page(api), status=200)
      }
      if route.has_prefix("/commit/") {
        let sha = String::unsafe_substring(
          route,
          start="/commit/".length(),
          end=route.length(),
        )
        let page = render_commit_detail_page(api, sha)
        return ctx.html(page.html, status=page.status)
      }
      if route == "/branches" {
        return ctx.html(render_branches_page(api), status=200)
      }
      if route == "/search" {
        let q = query_param(raw_path, "q").unwrap_or("")
        return ctx.html(render_search_page(api, q), status=200)
      }
      if route == "/issues" {
        return ctx.html(render_issues_page(api), status=200)
      }
      if route.has_prefix("/issues/") {
        let id = String::unsafe_substring(
          route,
          start="/issues/".length(),
          end=route.length(),
        )
        let page = render_issue_detail_page(api, id)
        return ctx.html(page.html, status=page.status)
      }
      if route == "/activity" {
        return ctx.html(render_activity_page(api), status=200)
      }
      if route.has_prefix("/compare/") {
        let spec = String::unsafe_substring(
          route,
          start="/compare/".length(),
          end=route.length(),
        )
        let page = render_compare_page(api, spec)
        return ctx.html(page.html, status=page.status)
      }
      if route == "/webhooks" {
        return ctx.html(render_webhooks_page(api), status=200)
      }
      if route == "/pulls" {
        return ctx.html(render_pulls_page(api), status=200)
      }
      if route.has_prefix("/pulls/") {
        let id = String::unsafe_substring(
          route,
          start="/pulls/".length(),
          end=route.length(),
        )
        let page = render_pull_detail_page(api, id)
        return ctx.html(page.html, status=page.status)
      }
      if route == "/tags" {
        return ctx.html(render_tags_page(api), status=200)
      }
      if route == "/stats" {
        return ctx.html(render_stats_page(api), status=200)
      }
      if route == "/feed.xml" {
        let base_url = match ctx.header("Host") {
          Some(host) => "https://" + host
          None => ""
        }
        ctx.set_header("Content-Type", "application/rss+xml; charset=utf-8")
        return ctx.text(api.activity_rss(base_url))
      }
      if route == "/blame" {
        let path = query_param(raw_path, "path").unwrap_or("")
        let page = render_blame_page(api, path)
        return ctx.html(page.html, status=page.status)
      }
      if route == "/actions/workflows" {
        return ctx.html(render_workflows_page(api), status=200)
      }
      if route.has_prefix("/actions/workflows/") {
        let file = String::unsafe_substring(
          route,
          start="/actions/workflows/".length(),
          end=route.length(),
        )
        let page = render_workflow_detail_page(api, file)
        return ctx.html(page.html, status=page.status)
      }
      if route.has_prefix("/actions/runs/") {
        let id = String::unsafe_substring(
          route,
          start="/actions/runs/".length(),
          end=route.length(),
        )
        let page = render_ci_run_detail_page(api, id)
        return ctx.html(page.html, status=page.status)
      }
      if route == "/actions" {
        return ctx.html(render_ci_page(api), status=200)
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
      @luna.h("li", [], [
        @components.link("/commits", [@luna.text("commits")]),
      ]),
      @luna.h("li", [], [
        @components.link("/branches", [@luna.text("branches")]),
      ]),
      @luna.h("li", [], [
        @components.link("/actions/workflows", [@luna.text("workflows")]),
      ]),
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
            @luna.text(" | "),
            @components.link("/commits", [@luna.text("commits")]),
            @luna.text(" | "),
            @components.link("/branches", [@luna.text("branches")]),
            @luna.text(" | "),
            @components.link("/issues", [@luna.text("issues")]),
            @luna.text(" | "),
            @components.link("/pulls", [@luna.text("pulls")]),
            @luna.text(" | "),
            @components.link("/activity", [@luna.text("activity")]),
            @luna.text(" | "),
            @components.link("/search?q=", [@luna.text("search")]),
            @luna.text(" | "),
            @components.link("/actions", [@luna.text("actions")]),
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
    #|.diff-add{color:#22863a;background:#f0fff4;}
    #|.diff-del{color:#cb2431;background:#ffeef0;}
    #|@media (prefers-color-scheme: dark){.diff-add{color:#85e89d;background:#144620;}.diff-del{color:#f97583;background:#3c1f23;}}
    #|code{font-family:ui-monospace,Menlo,monospace;}
    #|.wf-table{width:100%;border-collapse:collapse;}.wf-table th,.wf-table td{text-align:left;padding:8px 12px;border-bottom:1px solid var(--border);}.wf-table th{font-weight:600;}
    #|@media (max-width: 760px){body{padding:64px 10px 12px;height:auto;}main{min-height:auto;}footer{position:static;margin-top:12px;padding:8px 0 0;border-top:none;}}
  let terminal_css =
    #|#terminal-panel{display:none;position:fixed;bottom:0;left:0;right:0;height:40vh;z-index:100;background:#0d1117;border-top:2px solid #30363d;overflow:hidden;}
    #|#terminal-panel.open{display:flex;flex-direction:column;}
    #|#terminal-bar{display:flex;justify-content:space-between;align-items:center;padding:4px 12px;background:#161b22;border-bottom:1px solid #30363d;font-size:12px;color:#8b949e;font-family:ui-monospace,Menlo,monospace;}
    #|#terminal-bar button{background:none;border:none;color:#8b949e;cursor:pointer;font-size:14px;}
    #|#terminal-container{flex:1;overflow:hidden;}
  let terminal_js =
    #|<div id="terminal-panel"><div id="terminal-bar"><span>Terminal <small id="terminal-status"></small></span><button onclick="toggleTerminal()">✕</button></div><div id="terminal-container"></div></div>
    #|<script type="module">
    #|const panel=document.getElementById('terminal-panel');
    #|const container=document.getElementById('terminal-container');
    #|const status=document.getElementById('terminal-status');
    #|let term=null,resttyLoaded=false;
    #|
    #|async function ensureRestty(){
    #|  if(resttyLoaded)return true;
    #|  status.textContent='loading restty...';
    #|  try{
    #|    const{Restty,getBuiltinTheme}=await import('https://esm.sh/restty@0.1.34');
    #|    term=new Restty({root:container});
    #|    const theme=getBuiltinTheme('Aizen Dark');
    #|    if(theme)term.applyTheme(theme);
    #|    resttyLoaded=true;
    #|    status.textContent='';
    #|    // Wire up command handling
    #|    let line='';
    #|    term.writeln('\x1b[36mbithub terminal v0.2 — powered by restty\x1b[0m');
    #|    term.writeln('\x1b[90mType "help" for commands. Ctrl-` to toggle.\x1b[0m');
    #|    term.write('\r\n\x1b[34m$ \x1b[0m');
    #|    term.onData(async(data)=>{
    #|      if(data==='\r'||data==='\n'){
    #|        term.write('\r\n');
    #|        if(line.trim())await runCmd(line.trim());
    #|        line='';
    #|        term.write('\x1b[34m$ \x1b[0m');
    #|      }else if(data==='\x7f'){
    #|        if(line.length>0){line=line.slice(0,-1);term.write('\b \b');}
    #|      }else if(data.charCodeAt(0)>=32){
    #|        line+=data;term.write(data);
    #|      }
    #|    });
    #|    return true;
    #|  }catch(e){
    #|    status.textContent='restty failed: '+e.message;
    #|    console.error('restty load failed',e);
    #|    return false;
    #|  }
    #|}
    #|
    #|async function runCmd(input){
    #|  const[cmd,...args]=input.split(/\s+/);
    #|  const CMDS={
    #|    help:()=>term.writeln('\x1b[90mCommands: help, clear, init <owner/repo>, issues, activity, participants, repo\x1b[0m'),
    #|    clear:()=>term.clear(),
    #|    repo:async()=>{try{const r=await fetch('/_meta/repo');const m=await r.json();term.writeln(JSON.stringify(m,null,2));}catch{term.writeln('\x1b[31mNo repo initialized\x1b[0m');}},
    #|    issues:()=>{window.location.href='/issues';},
    #|    participants:async()=>{const repo=args[0]||'';const r=await fetch('/api/participants?repo='+repo);const d=await r.json().catch(()=>({}));const ps=d.participants||[];if(ps.length)ps.forEach(p=>term.writeln(p.participant_id+' ('+p.status+')'));else term.writeln('\x1b[90mNo active participants\x1b[0m');},
    #|    activity:async()=>{const repo=args[0]||'';const r=await fetch('/api/activity?repo='+repo);const d=await r.json().catch(()=>({}));const es=d.envelopes||[];if(es.length)es.forEach(e=>term.writeln('['+e.sender+'] '+e.topic+' '+e.id));else term.writeln('\x1b[90mNo recent activity\x1b[0m');},
    #|    init:async()=>{if(!args[0])return term.writeln('\x1b[31mUsage: init owner/repo\x1b[0m');term.writeln('\x1b[90mInitializing '+args[0]+'...\x1b[0m');const r=await fetch('/api/init?repo='+args[0],{method:'POST'});const d=await r.json().catch(()=>({}));term.writeln(d.ok?'\x1b[32mOK: '+d.files+' files loaded\x1b[0m':'\x1b[31mError: '+(d.error||'unknown')+'\x1b[0m');},
    #|  };
    #|  if(CMDS[cmd])await CMDS[cmd]();
    #|  else term.writeln('\x1b[31mUnknown: '+cmd+'. Type "help".\x1b[0m');
    #|}
    #|
    #|window.toggleTerminal=async function(){
    #|  const opening=!panel.classList.contains('open');
    #|  panel.classList.toggle('open');
    #|  if(opening)await ensureRestty();
    #|};
    #|document.addEventListener('keydown',e=>{if(e.key==='`'&&e.ctrlKey){e.preventDefault();toggleTerminal();}});
    #|</script>
  let head = "<meta charset=\"utf-8\"><style>" + css + terminal_css + "</style>"
  @sol.render_page(page, title~, head~) + terminal_js
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
fn format_timestamp(raw : String) -> String {
  if raw.length() == 0 {
    return ""
  }
  let mut epoch = 0L
  for c in raw {
    if c >= '0' && c <= '9' {
      epoch = epoch * 10L + (c.to_int() - '0'.to_int()).to_int64()
    } else {
      return raw
    }
  }
  if epoch == 0L {
    return raw
  }
  // Convert epoch seconds to YYYY-MM-DD HH:MM UTC
  let secs_per_min = 60L
  let secs_per_hour = 3600L
  let secs_per_day = 86400L
  let remaining = epoch
  let time_of_day = remaining % secs_per_day
  let mut days = remaining / secs_per_day
  let hour = time_of_day / secs_per_hour
  let minute = (time_of_day % secs_per_hour) / secs_per_min
  // Calculate year/month/day from days since 1970-01-01
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
    if n < 10L {
      "0" + n.to_string()
    } else {
      n.to_string()
    }
  }
  year.to_string() +
  "-" +
  pad2(month) +
  "-" +
  pad2(day) +
  " " +
  pad2(hour) +
  ":" +
  pad2(minute) +
  " UTC"
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
fn extract_json_string(json : Json, key : String) -> String {
  match json {
    Object(obj) =>
      match obj.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
fn render_diff_patch(patch : String) -> @luna.Node[Unit, String] {
  if patch.length() == 0 {
    return @luna.text("")
  }
  let lines : Array[@luna.Node[Unit, String]] = []
  for line_view in patch.split("\n") {
    let line = line_view.to_string()
    let cls = if line.has_prefix("+") {
      "diff-add"
    } else if line.has_prefix("-") {
      "diff-del"
    } else {
      ""
    }
    if cls.length() > 0 {
      lines.push(
        @luna.h("span", [("class", @luna.attr_static(cls))], [
          @luna.text(line + "\n"),
        ]),
      )
    } else {
      lines.push(@luna.text(line + "\n"))
    }
  }
  @luna.h("pre", [("class", @luna.attr_static("source-code"))], [
    @luna.h("code", [], lines),
  ])
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
