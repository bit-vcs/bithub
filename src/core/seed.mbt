///|
pub fn seed_files(kv : &Storage) -> Unit {
  let readme =
    #|# bithub
    #|
    #|A minimal self-browsing API/UI prototype powered by `bit kv`.
    #|
    #|- open `/filer` to browse this app
    #|- open `/file?path=src/core/api_state.mbt` to inspect core source
  kv.set_string("README.md", readme)
  let moon_mod =
    #|{
    #|  "name": "bit-vcs/bithub",
    #|  "preferred-target": "js",
    #|  "deps": {
    #|    "mizchi/bit": "0.21.2",
    #|    "mizchi/markdown": "0.4.7",
    #|    "mizchi/mars": "0.3.7"
    #|  }
    #|}
  kv.set_string("moon.mod.json", moon_mod)
  let core_source =
    #|pub struct RouteSpec {
    #|  id : String
    #|  http_method : String
    #|  path : String
    #|}
    #|
    #|pub fn mars_route_specs() -> Array[RouteSpec] {
    #|  [
    #|    { id: "home", http_method: "GET", path: "/" },
    #|    { id: "readme", http_method: "GET", path: "/readme" },
    #|    { id: "filer", http_method: "GET", path: "/filer" },
    #|  ]
    #|}
  kv.set_string("src/core/core.mbt", core_source)
  let api_state_source =
    #|pub struct FileLookup {
    #|  status : Int
    #|  path : String
    #|  content : String?
    #|}
    #|
    #|pub struct ApiState {
    #|  kv : @kv.Kv
    #|}
    #|
    #|pub fn ApiState::lookup_file(self : ApiState, path : String) -> FileLookup {
    #|  { status: 200, path, content: None }
    #|}
  kv.set_string("src/core/api_state.mbt", api_state_source)
  let mars_adapter =
    #|pub fn create_app() -> @mars.Server {
    #|  let app = @mars.Server::new()
    #|  let api = @core.ApiState::new()
    #|  let _ = app
    #|    ..get("/", fn(ctx) { ctx.html(@sol.render_page(@luna.text("bithub"))) })
    #|    ..get("/filer", fn(ctx) { ctx.html(@sol.render_page(@luna.text("filer"))) })
    #|  app
    #|}
  kv.set_string("src/adapters/mars_http/server.mbt", mars_adapter)
  let main_entry =
    #|pub fn fetch(
    #|  request : @mars.JsRequest,
    #|  env : @mars.JsEnv,
    #|  exec_ctx : @mars.JsExecCtx,
    #|) -> @js_async.Promise[@mars.JsResponse] {
    #|  let app = @mars_http.create_app()
    #|  let handler = app.to_handler_with_env(env, exec_ctx)
    #|  handler(request)
    #|}
  kv.set_string("src/cmd/main/main.mbt", main_entry)
  let ci_workflow =
    #|name: CI
    #|on:
    #|  push:
    #|    branches:
    #|      - main
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - uses: actions/checkout@v4
    #|      - name: Install dependencies
    #|        run: npm install
    #|      - name: Run tests
    #|        run: npm test
    #|      - name: Build
    #|        run: npm run build
    #|  lint:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - uses: actions/checkout@v4
    #|      - name: Lint
    #|        run: npm run lint
  kv.set_string(".github/workflows/ci.yml", ci_workflow)
  let deploy_workflow =
    #|name: Deploy
    #|on:
    #|  push:
    #|    branches:
    #|      - main
    #|    paths:
    #|      - src/**
    #|jobs:
    #|  deploy:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - uses: actions/checkout@v4
    #|      - name: Deploy to production
    #|        run: ./deploy.sh
  kv.set_string(".github/workflows/deploy.yml", deploy_workflow)
  let notes =
    #|Mars/Sol boundary note:
    #|- keep core pure
    #|- keep adapter replaceable
    #|- cloudflare js target first
  kv.set_string("docs/notes.txt", notes)
  // Seed: issues
  kv.set_string(
    "issues/1/meta",
    "title=Add relay webhook E2E tests\nstate=closed\nauthor=mizchi\ncreated_at=1773640000",
  )
  kv.set_string(
    "issues/1/body",
    "We need E2E tests for the relay webhook → CI run flow.\n\nShould cover:\n- Happy path (pending → success)\n- Failure propagation\n- Permission enforcement",
  )
  kv.set_string(
    "issues/1/comments/0",
    "author=ci-bot\nbody=Implemented in PR #2. 21 test cases added.\ncreated_at=1773650000",
  )
  kv.set_string(
    "issues/2/meta",
    "title=Support Cloudflare R2 as storage backend\nstate=open\nauthor=mizchi\ncreated_at=1773660000",
  )
  kv.set_string(
    "issues/2/body",
    "The Storage trait is ready. We need an R2 implementation that:\n- Uses Cloudflare R2 binding via FFI\n- Maps get/set_string/list/has to R2 API\n- Handles prefix listing efficiently",
  )
  // Seed: tags
  kv.set_string("git/tags/v0.1.0", "sha=ccc3456\nmessage=Initial release")
  kv.set_string("git/tags/v0.1.1", "sha=abc1234\nmessage=Bug fixes and CI improvements")
  // Seed: auth tokens
  kv.set_string("auth/tokens/tok-owner-001", "identity=mizchi\nrole=owner")
  kv.set_string("auth/tokens/tok-write-001", "identity=ci-bot\nrole=write")
  kv.set_string("auth/tokens/tok-read-001", "identity=viewer\nrole=read")
  kv.set_string("auth/tokens/tok-alice", "identity=agent-alice\nrole=owner")
  kv.set_string("auth/tokens/tok-bob", "identity=agent-bob\nrole=write")
  // Seed: branches
  kv.set_string(
    "git/branches/main",
    "sha=abc1234\ncurrent=true\nname=main",
  )
  kv.set_string(
    "git/branches/feat--ci-webhook",
    "sha=def5678\ncurrent=false\nname=feat/ci-webhook",
  )
  kv.set_string(
    "git/branches/fix--template-literal",
    "sha=aaa9999\ncurrent=false\nname=fix/template-literal",
  )
  // Seed: commits
  kv.set_string(
    "git/commits/abc1234",
    "message=feat: add relay webhook CI tracking\nauthor=mizchi <mz@example.com>\ntimestamp=1773660000\nparent=bbb2345",
  )
  kv.set_string(
    "git/commits/bbb2345",
    "message=fix: escape template literal in split resizer\nauthor=mizchi <mz@example.com>\ntimestamp=1773650000\nparent=ccc3456",
  )
  kv.set_string(
    "git/commits/ccc3456",
    "message=chore: update dependencies\nauthor=mizchi <mz@example.com>\ntimestamp=1773640000\nparent=",
  )
  // Seed: diffs for first commit
  kv.set_string(
    "git/diffs/abc1234/0",
    "path=src/core/ci.mbt\nkind=added\npatch=+pub fn process_relay_webhook(...)",
  )
  kv.set_string(
    "git/diffs/abc1234/1",
    "path=src/adapters/mars_http/server.mbt\nkind=modified\npatch=+app.post(\"/api/webhook/relay\", ...)",
  )
  kv.set_string(
    "git/diffs/bbb2345/0",
    "path=src/cmd/bithub/viewer.mbt\nkind=modified\npatch=-layout.style.setProperty('--sidebar-size', `${current}px`);\n+layout.style.setProperty('--sidebar-size', current + 'px');",
  )
}