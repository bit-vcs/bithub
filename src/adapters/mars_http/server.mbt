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
    "/api/files/sync",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          guard obj.get("files") is Some(Array(files_arr)) else {
            let e : Map[String, Json] = {}
            e.set("error", "missing files array".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let mut synced = 0
          for item in files_arr {
            guard item is Object(file_obj) else { continue }
            let path = match file_obj.get("path") {
              Some(String(s)) => s
              _ => continue
            }
            let content = match file_obj.get("content") {
              Some(String(s)) => s
              _ => continue
            }
            api.store.set_string(path, content)
            synced += 1
          }
          let resp : Map[String, Json] = {}
          resp.set("synced", synced.to_json())
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
      // Workspace: full SPA — serve same shell for all paths
      if route.has_prefix("/workspace/") {
        let rest = String::unsafe_substring(
          route,
          start="/workspace/".length(),
          end=route.length(),
        )
        let slash = find_char(rest, '/')
        let ws = if slash >= 0 {
          String::unsafe_substring(rest, start=0, end=slash)
        } else {
          rest
        }
        return ctx.html(render_workspace_spa(ws), status=200)
      }
      dispatch_route(api, ctx, route, raw_path)
    }),
  )
  app
}

///|
fn dispatch_route(
  api : @core.ApiState,
  ctx : @mars.Context,
  route : String,
  raw_path : String,
) -> Unit {
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
