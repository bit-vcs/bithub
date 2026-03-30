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

///| Assemble the full application: API routes + UI routes.
/// API routes (api_routes.mbt) are UI-independent JSON endpoints.
/// UI routes below can be swapped for a different frontend.
pub fn create_app_with_storage(api : @core.ApiState) -> @mars.Server {
  let app = @mars.Server::new()
  // Register API routes (pure JSON, no UI dependency)
  register_api_routes(app, api)
  // Register UI routes (HTML pages + SPA)
  register_ui_routes(app, api)
  app
}

///| Register all GET routes that serve HTML pages.
/// This is the UI layer — depends on luna/mars/markdown for rendering.
/// Can be replaced with a different UI implementation.
fn register_ui_routes(app : @mars.Server, api : @core.ApiState) -> Unit {
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
  if route == "/releases" {
    return ctx.html(render_releases_page(api), status=200)
  }
  if route.has_prefix("/releases/") {
    let id = String::unsafe_substring(
      route,
      start="/releases/".length(),
      end=route.length(),
    )
    let page = render_release_detail_page(api, id)
    return ctx.html(page.html, status=page.status)
  }
  if route == "/labels" {
    return ctx.html(render_labels_page(api), status=200)
  }
  if route == "/milestones" {
    return ctx.html(render_milestones_page(api), status=200)
  }
  if route.has_prefix("/milestones/") {
    let id = String::unsafe_substring(
      route,
      start="/milestones/".length(),
      end=route.length(),
    )
    let page = render_milestone_detail_page(api, id)
    return ctx.html(page.html, status=page.status)
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
