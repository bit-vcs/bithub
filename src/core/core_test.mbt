///|
test "mars_route_specs contains API routes" {
  let routes = mars_route_specs()
  inspect(routes.length(), content="17")
  inspect(routes[0].http_method, content="GET")
  inspect(routes[0].path, content="/")
  inspect(routes[1].http_method, content="GET")
  inspect(routes[1].path, content="/healthz")
  inspect(routes[2].path, content="/readme")
  inspect(routes[3].path, content="/filer")
  inspect(routes[4].path, content="/file")
  inspect(routes[5].path, content="/actions")
  inspect(routes[6].path, content="/actions/workflows")
  inspect(routes[7].path, content="/actions/workflows/:file")
  inspect(routes[8].path, content="/actions/runs/:id")
  inspect(routes[9].path, content="/commits")
  inspect(routes[10].path, content="/commit/:sha")
  inspect(routes[11].path, content="/branches")
  inspect(routes[12].path, content="/blame")
  // POST routes at the end
  let post_routes = routes.filter(fn(r) { r.http_method == "POST" })
  assert_true(post_routes.length() >= 2)
  assert_true(
    post_routes.filter(fn(r) { r.path == "/api/webhook/relay" }).length() == 1,
  )
  assert_true(
    post_routes
    .filter(fn(r) { r.path == "/api/actions/runs/status" })
    .length() ==
    1,
  )
}

///|
test "texts are stable for adapter boundary" {
  inspect(home_text(), content="bithub: mars-first bootstrap")
  inspect(healthz_text(), content="ok")
}

///|
test "ApiState exposes README markdown text" {
  let api = ApiState::new()
  let markdown = api.readme_markdown()
  assert_true(markdown.contains("# bithub"))
  assert_true(markdown.contains("minimal self-browsing API"))
}

///|
test "ApiState lists filer entries as data" {
  let api = ApiState::new()
  let root = api.list_entries("")
  assert_true(root.any(fn(entry) { entry.name == "README.md" && not(entry.is_dir) }))
  assert_true(root.any(fn(entry) { entry.name == "moon.mod.json" && not(entry.is_dir) }))
  assert_true(root.any(fn(entry) { entry.name == "src" && entry.is_dir }))

  let core = api.list_entries("src/core")
  assert_true(
    core.any(fn(entry) {
      entry.name == "api_state.mbt" &&
      entry.path == "src/core/api_state.mbt" &&
      not(entry.is_dir)
    }),
  )
}

///|
test "ApiState lookup_file returns content with status" {
  let api = ApiState::new()
  let found = api.lookup_file("src/core/api_state.mbt")
  inspect(found.status, content="200")
  assert_eq(found.path, "src/core/api_state.mbt")
  assert_true(
    match found.content {
      Some(text) => text.contains("pub struct ApiState")
      None => false
    },
  )

  let missing = api.lookup_file("missing.txt")
  inspect(missing.status, content="404")
  assert_eq(missing.path, "missing.txt")
  assert_eq(missing.content, None)

  let empty = api.lookup_file("")
  inspect(empty.status, content="404")
  assert_eq(empty.content, None)
}

///|
test "ApiState lists workflows from seed data" {
  let api = ApiState::new()
  let workflows = api.list_workflows()
  inspect(workflows.length(), content="2")
  let ci = workflows[0]
  inspect(ci.filename, content="ci.yml")
  inspect(ci.name, content="CI")
  inspect(ci.job_count, content="2")
  assert_true(ci.triggers.contains("push"))
  let deploy = workflows[1]
  inspect(deploy.filename, content="deploy.yml")
  inspect(deploy.name, content="Deploy")
  inspect(deploy.job_count, content="1")
}

///|
test "ApiState workflow_detail returns job and step info" {
  let api = ApiState::new()
  let detail = api.workflow_detail("ci.yml").unwrap()
  inspect(detail.name, content="CI")
  inspect(detail.jobs.length(), content="2")
  let build = detail.jobs[0]
  inspect(build.id, content="build")
  inspect(build.step_count, content="4")
  inspect(build.steps[0].uses, content="Some(\"actions/checkout@v4\")")
  inspect(build.steps[1].name, content="Install dependencies")
}

///|
test "ApiState workflow_detail returns None for missing file" {
  let api = ApiState::new()
  assert_true(api.workflow_detail("nonexistent.yml").is_empty())
}

///|
test "extract_branch_from_relay_ref extracts branch name" {
  inspect(
    extract_branch_from_relay_ref("refs/relay/incoming/main"),
    content="Some(\"main\")",
  )
  inspect(
    extract_branch_from_relay_ref("refs/relay/incoming/feature/foo"),
    content="Some(\"feature/foo\")",
  )
  inspect(extract_branch_from_relay_ref("refs/heads/main"), content="None")
  inspect(extract_branch_from_relay_ref(""), content="None")
}

///|
fn make_relay_webhook(
  event_id : String,
  relay_ref : String,
  event_type~ : String = "relay.incoming_ref",
  source~ : String = "deno:127.0.0.1:8788",
) -> Json {
  let obj : Map[String, Json] = {}
  obj.set("event_type", event_type.to_json())
  obj.set("event_id", event_id.to_json())
  obj.set("occurred_at", (1700000000).to_json())
  obj.set("ref", relay_ref.to_json())
  obj.set("source", source.to_json())
  obj.set("room", "main".to_json())
  obj.set("target", "session:abc123".to_json())
  obj.to_json()
}

///|
fn find_job(
  detail : CiRunDetail,
  job_id : String,
) -> CiJobRunDetail? {
  for jd in detail.jobs {
    if jd.job.job_id == job_id {
      return Some(jd)
    }
  }
  None
}

///|
test "process_relay_webhook matches ci.yml and creates job/step entries" {
  let api = ApiState::new()
  let json = make_relay_webhook("evt-001", "refs/relay/incoming/main")
  let runs = api.process_relay_webhook(json)
  inspect(runs.length(), content="1")
  inspect(runs[0].workflow_file, content="ci.yml")
  inspect(runs[0].workflow_name, content="CI")
  inspect(runs[0].ref_name, content="main")
  inspect(runs[0].status, content="pending")
  inspect(runs[0].id, content="evt-001")
  // Verify job/step detail was created
  let detail = api.get_ci_run_detail("evt-001").unwrap()
  inspect(detail.jobs.length(), content="2")
  let build = find_job(detail, "build").unwrap()
  inspect(build.job.status, content="pending")
  inspect(build.steps.length(), content="4")
  inspect(build.steps[0].uses, content="actions/checkout@v4")
  inspect(build.steps[1].name, content="Install dependencies")
  inspect(build.steps[1].run_cmd, content="npm install")
  let lint = find_job(detail, "lint").unwrap()
  inspect(lint.steps.length(), content="2")
  inspect(lint.steps[1].name, content="Lint")
  inspect(lint.steps[1].run_cmd, content="npm run lint")
}

///|
test "process_relay_webhook ignores invalid event types" {
  let api = ApiState::new()
  let json = make_relay_webhook(
    "evt-002",
    "refs/relay/incoming/main",
    event_type="other.event",
  )
  let runs = api.process_relay_webhook(json)
  inspect(runs.length(), content="0")
}

///|
test "list_ci_runs returns saved runs" {
  let api = ApiState::new()
  let json = make_relay_webhook("evt-010", "refs/relay/incoming/main")
  let _ = api.process_relay_webhook(json)
  let runs = api.list_ci_runs()
  inspect(runs.length(), content="1")
  inspect(runs[0].id, content="evt-010")
  inspect(runs[0].workflow_file, content="ci.yml")
}

///|
test "get_ci_run retrieves a specific run" {
  let api = ApiState::new()
  let json = make_relay_webhook("evt-020", "refs/relay/incoming/main")
  let _ = api.process_relay_webhook(json)
  let run = api.get_ci_run("evt-020")
  assert_true(run.is_empty() |> not)
  inspect(run.unwrap().workflow_name, content="CI")
  assert_true(api.get_ci_run("nonexistent").is_empty())
}

///|
test "update_step_status propagates to job and run" {
  let api = ApiState::new()
  let json = make_relay_webhook("evt-030", "refs/relay/incoming/main")
  let _ = api.process_relay_webhook(json)
  // Mark first step of build as running
  let ok = api.update_step_status("evt-030", "build", 0, "running", "100")
  assert_true(ok)
  let detail = api.get_ci_run_detail("evt-030").unwrap()
  let build = find_job(detail, "build").unwrap()
  inspect(build.steps[0].status, content="running")
  inspect(build.job.status, content="running")
  inspect(detail.run.status, content="running")
  // Mark all build steps as success
  let _ = api.update_step_status("evt-030", "build", 0, "success", "101")
  let _ = api.update_step_status("evt-030", "build", 1, "success", "102")
  let _ = api.update_step_status("evt-030", "build", 2, "success", "103")
  let _ = api.update_step_status("evt-030", "build", 3, "success", "104")
  let d2 = api.get_ci_run_detail("evt-030").unwrap()
  inspect(find_job(d2, "build").unwrap().job.status, content="success")
  // lint still pending, so run is still pending
  inspect(d2.run.status, content="pending")
  // Complete lint job too
  let _ = api.update_step_status("evt-030", "lint", 0, "success", "105")
  let _ = api.update_step_status("evt-030", "lint", 1, "success", "106")
  let d3 = api.get_ci_run_detail("evt-030").unwrap()
  inspect(find_job(d3, "lint").unwrap().job.status, content="success")
  inspect(d3.run.status, content="success")
}

///|
test "update_step_status failure propagates" {
  let api = ApiState::new()
  let json = make_relay_webhook("evt-040", "refs/relay/incoming/main")
  let _ = api.process_relay_webhook(json)
  let _ = api.update_step_status("evt-040", "build", 0, "success", "100")
  let _ = api.update_step_status("evt-040", "build", 1, "failure", "101")
  let detail = api.get_ci_run_detail("evt-040").unwrap()
  inspect(find_job(detail, "build").unwrap().job.status, content="failure")
}

///|
test "get_ci_run_detail returns None for missing run" {
  let api = ApiState::new()
  assert_true(api.get_ci_run_detail("nonexistent") is None)
}

// ---- Storage trait tests ----

///|
fn test_storage() -> &Storage {
  MapStorage::new()
}

///|
test "MapStorage: get/set/has/list" {
  let s = test_storage()
  assert_true(s.get("foo") is None)
  assert_true(not(s.has("foo")))
  s.set_string("foo", "bar")
  assert_true(s.has("foo"))
  let bytes = s.get("foo").unwrap()
  inspect(@utf8.decode_lossy(bytes), content="bar")
}

///|
test "MapStorage: list returns child keys at one level" {
  let s = test_storage()
  s.set_string("a/b/c", "1")
  s.set_string("a/b/d", "2")
  s.set_string("a/x", "3")
  s.set_string("z", "4")
  let children = s.list("a")
  children.sort_by(fn(a, b) { String::compare(a, b) })
  inspect(children, content="[\"b\", \"x\"]")
  let grandchildren = s.list("a/b")
  grandchildren.sort_by(fn(a, b) { String::compare(a, b) })
  inspect(grandchildren, content="[\"c\", \"d\"]")
  let root = s.list("")
  root.sort_by(fn(a, b) { String::compare(a, b) })
  inspect(root, content="[\"a\", \"z\"]")
}

///|
extern "js" fn rm_rf(path : String) -> Unit =
  #| (path) => { try { require("node:fs").rmSync(path, { recursive: true }); } catch {} }

///|
test "FsStorage: get/set/has/list round-trip" {
  let dir = "/tmp/bithub-fs-test-unit"
  rm_rf(dir)
  let s : &Storage = FsStorage::new(dir)
  assert_true(s.get("foo") is None)
  assert_true(not(s.has("foo")))
  s.set_string("foo", "bar")
  assert_true(s.has("foo"))
  let bytes = s.get("foo").unwrap()
  inspect(@utf8.decode_lossy(bytes), content="bar")
  // nested keys
  s.set_string("a/b/c", "nested")
  assert_true(s.has("a/b/c"))
  let children = s.list("a")
  inspect(children, content="[\"b\"]")
  let grandchildren = s.list("a/b")
  inspect(grandchildren, content="[\"c\"]")
}

///|
test "ApiState works with MapStorage backend" {
  let s : &Storage = MapStorage::new()
  s.set_string("README.md", "# test")
  s.set_string(
    ".github/workflows/ci.yml",
    "name: CI\non:\n  push:\n    branches:\n      - main\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4\n      - name: Test\n        run: echo ok",
  )
  s.set_string("auth/tokens/test-tok", "identity=tester\nrole=write")
  let api = ApiState::with_storage(s)
  inspect(api.readme_markdown(), content="# test")
  // Auth works
  let auth = api.authenticate(Some("Bearer test-tok"))
  assert_true(auth is Authenticated(_))
  // Workflows detected
  let wfs = api.list_workflows()
  inspect(wfs.length(), content="1")
  inspect(wfs[0].name, content="CI")
}
