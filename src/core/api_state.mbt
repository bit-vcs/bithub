///|
pub struct FileEntry {
  name : String
  path : String
  is_dir : Bool
}

///|
pub struct FileLookup {
  status : Int
  path : String
  content : String?
}

///|
// Adapter: @bitfs.Fs -> @bitlib.WorkingTree
priv struct KvWorkingTree {
  fs : @bitfs.Fs
  backing_fs : &@bit.RepoFileSystem
  write_fs : &@bit.FileSystem
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with read_file(self, path) {
  self.fs.read_file(self.backing_fs, path)
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with write_file(self, path, data) {
  self.fs.write_file(path, data)
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with remove_file(self, path) {
  self.fs.remove_file(path)
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with is_file(self, path) {
  self.fs.is_file(self.backing_fs, path)
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with is_dir(self, path) {
  self.fs.is_dir(self.backing_fs, path)
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with readdir(self, path) {
  self.fs.readdir(self.backing_fs, path)
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with is_dirty(self) {
  self.fs.is_dirty()
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with rollback(self) {
  self.fs.rollback()
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with get_working_files(self) {
  self.fs.get_working_files()
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with snapshot(
  self,
  message,
  author,
  timestamp,
) {
  let snapshot = self.fs.snapshot(
    self.write_fs,
    self.backing_fs,
    message,
    author,
    timestamp,
  )
  snapshot.commit_id
}

///|
impl @bitlib.WorkingTree for KvWorkingTree with checkout(self, commit_id) {
  self.fs.checkout_snapshot(self.backing_fs, commit_id)
}

///|
// Adapter: filesystem object db -> @bitlib.ObjectStore
priv struct KvObjectStore {
  backing_fs : &@bit.RepoFileSystem
  write_fs : &@bit.FileSystem
  git_dir : String
}

///|
impl @bitlib.ObjectStore for KvObjectStore with get(self, id) {
  let db = @bitlib.ObjectDb::load(self.backing_fs, self.git_dir)
  db.get(self.backing_fs, id)
}

///|
impl @bitlib.ObjectStore for KvObjectStore with put(self, obj_type, data) {
  @bitlib.write_loose_object(self.write_fs, self.git_dir, obj_type, data)
}

///|
impl @bitlib.ObjectStore for KvObjectStore with has(self, id) {
  let db = @bitlib.ObjectDb::load(self.backing_fs, self.git_dir) catch {
    _ => return false
  }
  let obj = db.get(self.backing_fs, id) catch { _ => return false }
  obj is Some(_)
}

///|
pub struct ApiState {
  store : &Storage
}

///|
pub fn ApiState::new() -> ApiState {
  { store: MemoryStorage::new_seeded() }
}

///|
pub fn ApiState::with_storage(store : &Storage) -> ApiState {
  { store, }
}

///|
/// Create ApiState populated from a real git repository on disk.
/// Reads commits, branches, and files from the repo at `root`.
pub fn ApiState::from_repo(root : String) -> ApiState {
  let store : &Storage = MapStorage::new()
  let git_dir = root + "/.git"
  let node_fs = NodeFs::new()
  // Scan and load files
  let files = scan_files(root)
  ignore(files.length())
  load_files_into_storage(store, root, files)
  // Load workflow files (may be in .github which scan_files skips)
  match read_file_string(root + "/.github/workflows/ci.yml") {
    Some(content) => store.set_string(".github/workflows/ci.yml", content)
    None => ()
  }
  // Load git data from real repository
  load_git_commits_into_storage(store, node_fs, git_dir)
  load_git_branches_into_storage(store, node_fs, git_dir)
  // Add default auth token
  store.set_string("auth/tokens/tok-owner-001", "identity=admin\nrole=owner")
  store.set_string("auth/tokens/tok-write-001", "identity=ci-bot\nrole=write")
  { store, }
}

///|
pub fn ApiState::readme_markdown(self : ApiState) -> String {
  self.file_text("README.md").unwrap_or("# README.md\n\nnot found")
}

///|
pub fn ApiState::lookup_file(
  self : ApiState,
  raw_path : String,
) -> FileLookup {
  let path = normalize_path(raw_path)
  if path.length() == 0 {
    return { status: 404, path, content: None }
  }
  match self.file_text(path) {
    Some(content) => { status: 200, path, content: Some(content) }
    None => { status: 404, path, content: None }
  }
}

///|
pub fn ApiState::list_entries(
  self : ApiState,
  raw_path : String,
) -> Array[FileEntry] {
  let path = normalize_path(raw_path)
  let names = self.store.list(path)
  names.sort_by(fn(a, b) { String::compare(a, b) })
  let entries : Array[FileEntry] = []
  for name in names {
    let full_path = join_path(path, name)
    entries.push({ name, path: full_path, is_dir: not(self.store.has(full_path)) })
  }
  entries
}

///|
pub fn ApiState::file_text(self : ApiState, raw_path : String) -> String? {
  let path = normalize_path(raw_path)
  match self.store.get(path) {
    Some(bytes) => Some(@utf8.decode_lossy(bytes))
    None => None
  }
}

///|
fn seed_files(kv : &Storage) -> Unit {
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

// ---- Permissions ----

///|
pub enum Role {
  Owner
  Write
  Read
} derive(Eq)

///|
pub fn Role::to_string(self : Role) -> String {
  match self {
    Owner => "owner"
    Write => "write"
    Read => "read"
  }
}

///|
pub fn Role::can_write(self : Role) -> Bool {
  match self {
    Owner | Write => true
    Read => false
  }
}

///|
pub fn Role::can_admin(self : Role) -> Bool {
  self is Owner
}

///|
pub struct TokenInfo {
  identity : String
  role : Role
}

///|
pub fn ApiState::resolve_token(self : ApiState, token : String) -> TokenInfo? {
  if token.length() == 0 {
    return None
  }
  match self.store.get("auth/tokens/" + token) {
    Some(bytes) => {
      let text = @utf8.decode_lossy(bytes)
      let fields = parse_kv_fields(text)
      let identity = fields.get("identity").unwrap_or("")
      let role_str = fields.get("role").unwrap_or("read")
      let role = match role_str {
        "owner" => Owner
        "write" => Write
        _ => Read
      }
      if identity.length() > 0 {
        Some({ identity, role })
      } else {
        None
      }
    }
    None => None
  }
}

///|
pub fn ApiState::list_tokens(self : ApiState) -> Array[TokenInfo] {
  let names = self.store.list("auth/tokens")
  let entries : Array[TokenInfo] = []
  for name in names {
    match self.store.get("auth/tokens/" + name) {
      Some(bytes) => {
        let text = @utf8.decode_lossy(bytes)
        let fields = parse_kv_fields(text)
        let identity = fields.get("identity").unwrap_or("")
        let role_str = fields.get("role").unwrap_or("read")
        let role : Role = match role_str {
          "owner" => Owner
          "write" => Write
          _ => Read
        }
        if identity.length() > 0 {
          entries.push({ identity, role })
        }
      }
      None => ()
    }
  }
  entries
}

///|
pub enum AuthResult {
  Authenticated(TokenInfo)
  Anonymous
  InvalidToken
}

///|
pub fn ApiState::authenticate(
  self : ApiState,
  auth_header : String?,
) -> AuthResult {
  match auth_header {
    None => Anonymous
    Some(header) => {
      let token = extract_bearer_token(header)
      match token {
        None => InvalidToken
        Some(t) =>
          match self.resolve_token(t) {
            Some(info) => Authenticated(info)
            None => InvalidToken
          }
      }
    }
  }
}

///|
fn extract_bearer_token(header : String) -> String? {
  if header.has_prefix("Bearer ") {
    Some(String::unsafe_substring(header, start=7, end=header.length()))
  } else if header.has_prefix("bearer ") {
    Some(String::unsafe_substring(header, start=7, end=header.length()))
  } else {
    None
  }
}

// ---- Commits ----

///|
pub struct CommitEntry {
  sha : String
  message : String
  author : String
  timestamp : String
}

///|
pub struct CommitDetail {
  commit : CommitEntry
  parent_sha : String
  diff_files : Array[DiffFileEntry]
}

///|
pub struct DiffFileEntry {
  path : String
  kind : String // "added", "modified", "deleted"
  patch : String
}

///|
pub fn ApiState::list_commits(self : ApiState) -> Array[CommitEntry] {
  let shas = self.store.list("git/commits")
  let entries : Array[CommitEntry] = []
  for sha in shas {
    match self.store.get("git/commits/" + sha) {
      Some(bytes) => {
        let text = @utf8.decode_lossy(bytes)
        match parse_commit_entry(text, sha) {
          Some(entry) => entries.push(entry)
          None => ()
        }
      }
      None => ()
    }
  }
  entries.sort_by(fn(a, b) { String::compare(b.timestamp, a.timestamp) })
  entries
}

///|
pub fn ApiState::get_commit(self : ApiState, sha : String) -> CommitDetail? {
  match self.store.get("git/commits/" + sha) {
    Some(bytes) => {
      let text = @utf8.decode_lossy(bytes)
      match parse_commit_entry(text, sha) {
        Some(commit) => {
          let fields = parse_kv_fields(text)
          let parent = fields.get("parent").unwrap_or("")
          let diff_files : Array[DiffFileEntry] = []
          let diff_keys = self.store.list("git/diffs/" + sha)
          for dk in diff_keys {
            match self.store.get("git/diffs/" + sha + "/" + dk) {
              Some(dbytes) => {
                let dt = @utf8.decode_lossy(dbytes)
                let df = parse_kv_fields(dt)
                diff_files.push({
                  path: df.get("path").unwrap_or(dk),
                  kind: df.get("kind").unwrap_or("modified"),
                  patch: df.get("patch").unwrap_or(""),
                })
              }
              None => ()
            }
          }
          Some({ commit, parent_sha: parent, diff_files })
        }
        None => None
      }
    }
    None => None
  }
}

///|
fn parse_commit_entry(text : String, sha : String) -> CommitEntry? {
  let fields = parse_kv_fields(text)
  let message = fields.get("message").unwrap_or("")
  let author = fields.get("author").unwrap_or("")
  let timestamp = fields.get("timestamp").unwrap_or("")
  if message.length() == 0 && author.length() == 0 {
    return None
  }
  Some({ sha, message, author, timestamp })
}

// ---- Branches ----

///|
pub struct BranchEntry {
  name : String
  sha : String
  current : Bool
}

///|
pub fn ApiState::list_branches(self : ApiState) -> Array[BranchEntry] {
  let names = self.store.list("git/branches")
  let entries : Array[BranchEntry] = []
  for name in names {
    match self.store.get("git/branches/" + name) {
      Some(bytes) => {
        let text = @utf8.decode_lossy(bytes)
        let fields = parse_kv_fields(text)
        entries.push({
          name: fields.get("name").unwrap_or(name),
          sha: fields.get("sha").unwrap_or(""),
          current: fields.get("current").unwrap_or("") == "true",
        })
      }
      None => ()
    }
  }
  entries.sort_by(fn(a, b) {
    if a.current && not(b.current) {
      return -1
    }
    if not(a.current) && b.current {
      return 1
    }
    String::compare(a.name, b.name)
  })
  entries
}

///|
pub struct WorkflowEntry {
  filename : String
  name : String
  job_count : Int
  triggers : Array[String]
}

///|
pub struct WorkflowDetail {
  filename : String
  name : String
  triggers : Array[String]
  jobs : Array[WorkflowJobSummary]
}

///|
pub struct WorkflowJobSummary {
  id : String
  name : String
  runs_on : Array[String]
  step_count : Int
  steps : Array[WorkflowStepSummary]
}

///|
pub struct WorkflowStepSummary {
  id : String
  name : String
  uses : String?
  run_preview : String?
}

///|
pub fn ApiState::list_workflows(self : ApiState) -> Array[WorkflowEntry] {
  let entries : Array[WorkflowEntry] = []
  let workflow_dir = ".github/workflows"
  let names = self.store.list(workflow_dir)
  names.sort_by(fn(a, b) { String::compare(a, b) })
  for name in names {
    let path = workflow_dir + "/" + name
    if not(name.has_suffix(".yml") || name.has_suffix(".yaml")) {
      continue
    }
    match self.store.get(path) {
      Some(bytes) => {
        let text = @utf8.decode_lossy(bytes)
        let result = @actrun.parse_workflow_yaml(text)
        match result.workflow {
          Some(wf) => {
            let triggers = collect_triggers(wf)
            entries.push({
              filename: name,
              name: if wf.name.length() > 0 { wf.name } else { name },
              job_count: wf.jobs.length(),
              triggers,
            })
          }
          None => {
            entries.push({
              filename: name,
              name: name,
              job_count: 0,
              triggers: ["(parse error)"],
            })
          }
        }
      }
      None => ()
    }
  }
  entries
}

///|
pub fn ApiState::workflow_detail(
  self : ApiState,
  filename : String,
) -> WorkflowDetail? {
  let path = ".github/workflows/" + filename
  match self.store.get(path) {
    Some(bytes) => {
      let text = @utf8.decode_lossy(bytes)
      let result = @actrun.parse_workflow_yaml(text)
      match result.workflow {
        Some(wf) => {
          let jobs : Array[WorkflowJobSummary] = []
          for job in wf.jobs {
            let steps : Array[WorkflowStepSummary] = []
            for step in job.steps {
              let run_preview = match step.run {
                Some(r) =>
                  if r.length() > 60 {
                    Some(
                      String::unsafe_substring(r, start=0, end=60) + "...",
                    )
                  } else {
                    Some(r)
                  }
                None => None
              }
              steps.push({
                id: step.id,
                name: step.name,
                uses: step.uses,
                run_preview,
              })
            }
            jobs.push({
              id: job.id,
              name: if job.name.length() > 0 { job.name } else { job.id },
              runs_on: job.runs_on,
              step_count: job.steps.length(),
              steps,
            })
          }
          Some({
            filename,
            name: if wf.name.length() > 0 { wf.name } else { filename },
            triggers: collect_triggers(wf),
            jobs,
          })
        }
        None => None
      }
    }
    None => None
  }
}

///|
fn collect_triggers(wf : @actrun.WorkflowSpec) -> Array[String] {
  let triggers : Array[String] = []
  if wf.trigger.branches.length() > 0 ||
    wf.trigger.branches_ignore.length() > 0 ||
    wf.trigger.paths.length() > 0 ||
    wf.trigger.paths_ignore.length() > 0 {
    triggers.push("push")
  }
  if wf.workflow_call {
    triggers.push("workflow_call")
  }
  if triggers.length() == 0 {
    triggers.push("push")
  }
  triggers
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
fn join_path(parent : String, child : String) -> String {
  if parent.length() == 0 {
    child
  } else {
    parent + "/" + child
  }
}

// ---- Code Search ----

///|
pub struct SearchResult {
  path : String
  line_number : Int
  line : String
}

///|
pub fn ApiState::search(
  self : ApiState,
  query : String,
  max_results~ : Int = 50,
) -> Array[SearchResult] {
  if query.length() == 0 {
    return []
  }
  let results : Array[SearchResult] = []
  collect_search_results(self.store, "", query, results, max_results)
  results
}

///|
fn collect_search_results(
  store : &Storage,
  prefix : String,
  query : String,
  results : Array[SearchResult],
  max_results : Int,
) -> Unit {
  if results.length() >= max_results {
    return
  }
  let names = store.list(prefix)
  names.sort_by(fn(a, b) { String::compare(a, b) })
  for name in names {
    if results.length() >= max_results {
      return
    }
    let full_path = join_path(prefix, name)
    if store.has(full_path) {
      // It's a file — search content
      match store.get(full_path) {
        Some(bytes) => {
          let text = @utf8.decode_lossy(bytes)
          let mut line_num = 1
          for line_view in text.split("\n") {
            if results.length() >= max_results {
              return
            }
            let line = line_view.to_string()
            if string_contains(line, query) {
              results.push({ path: full_path, line_number: line_num, line })
            }
            line_num += 1
          }
        }
        None => ()
      }
    } else {
      // It's a directory — recurse
      collect_search_results(store, full_path, query, results, max_results)
    }
  }
}

///|
fn string_contains(haystack : String, needle : String) -> Bool {
  if needle.length() == 0 {
    return true
  }
  if needle.length() > haystack.length() {
    return false
  }
  let limit = haystack.length() - needle.length()
  for i = 0; i <= limit; i = i + 1 {
    let mut matched = true
    for j = 0; j < needle.length(); j = j + 1 {
      if haystack.unsafe_get(i + j) != needle.unsafe_get(j) {
        matched = false
        break
      }
    }
    if matched {
      return true
    }
  }
  false
}

// ---- Issues ----

///|
pub struct IssueEntry {
  id : String
  title : String
  state : String
  body : String
  author : String
  created_at : String
}

///|
pub struct IssueComment {
  author : String
  body : String
  created_at : String
}

///|
pub struct IssueDetail {
  issue : IssueEntry
  comments : Array[IssueComment]
}

///|
pub fn ApiState::list_issues(self : ApiState) -> Array[IssueEntry] {
  let ids = self.store.list("issues")
  let entries : Array[IssueEntry] = []
  for id in ids {
    match self.store.get("issues/" + id + "/meta") {
      Some(bytes) => {
        let fields = parse_kv_fields(@utf8.decode_lossy(bytes))
        entries.push({
          id,
          title: fields.get("title").unwrap_or(""),
          state: fields.get("state").unwrap_or("open"),
          body: "",
          author: fields.get("author").unwrap_or(""),
          created_at: fields.get("created_at").unwrap_or(""),
        })
      }
      None => ()
    }
  }
  entries.sort_by(fn(a, b) { String::compare(b.created_at, a.created_at) })
  entries
}

///|
pub fn ApiState::get_issue(self : ApiState, id : String) -> IssueDetail? {
  match self.store.get("issues/" + id + "/meta") {
    Some(bytes) => {
      let fields = parse_kv_fields(@utf8.decode_lossy(bytes))
      let body = match self.store.get("issues/" + id + "/body") {
        Some(b) => @utf8.decode_lossy(b)
        None => ""
      }
      let issue : IssueEntry = {
        id,
        title: fields.get("title").unwrap_or(""),
        state: fields.get("state").unwrap_or("open"),
        body,
        author: fields.get("author").unwrap_or(""),
        created_at: fields.get("created_at").unwrap_or(""),
      }
      let comment_ids = self.store.list("issues/" + id + "/comments")
      let comments : Array[IssueComment] = []
      for cid in comment_ids {
        match self.store.get("issues/" + id + "/comments/" + cid) {
          Some(cbytes) => {
            let cf = parse_kv_fields(@utf8.decode_lossy(cbytes))
            comments.push({
              author: cf.get("author").unwrap_or(""),
              body: cf.get("body").unwrap_or(""),
              created_at: cf.get("created_at").unwrap_or(""),
            })
          }
          None => ()
        }
      }
      Some({ issue, comments })
    }
    None => None
  }
}

///|
pub fn ApiState::create_issue(
  self : ApiState,
  title : String,
  body : String,
  author : String,
  timestamp : String,
) -> String {
  // Generate next issue ID by counting existing issues
  let existing = self.store.list("issues")
  let mut max_id = 0
  for id_str in existing {
    let mut n = 0
    for c in id_str {
      if c >= '0' && c <= '9' {
        n = n * 10 + (c.to_int() - '0'.to_int())
      }
    }
    if n > max_id {
      max_id = n
    }
  }
  let new_id = (max_id + 1).to_string()
  let meta = [
    "title=" + title,
    "state=open",
    "author=" + author,
    "created_at=" + timestamp,
  ].join("\n")
  self.store.set_string("issues/" + new_id + "/meta", meta)
  if body.length() > 0 {
    self.store.set_string("issues/" + new_id + "/body", body)
  }
  new_id
}

///|
pub fn ApiState::add_comment(
  self : ApiState,
  issue_id : String,
  author : String,
  body : String,
  timestamp : String,
) -> Bool {
  // Verify issue exists
  if self.store.get("issues/" + issue_id + "/meta") is None {
    return false
  }
  let existing = self.store.list("issues/" + issue_id + "/comments")
  let next_id = existing.length().to_string()
  let comment = [
    "author=" + author,
    "body=" + body,
    "created_at=" + timestamp,
  ].join("\n")
  self.store.set_string(
    "issues/" + issue_id + "/comments/" + next_id,
    comment,
  )
  true
}

///|
pub fn ApiState::update_issue_state(
  self : ApiState,
  id : String,
  new_state : String,
) -> Bool {
  match self.store.get("issues/" + id + "/meta") {
    Some(bytes) => {
      let fields = parse_kv_fields(@utf8.decode_lossy(bytes))
      let meta = [
        "title=" + fields.get("title").unwrap_or(""),
        "state=" + new_state,
        "author=" + fields.get("author").unwrap_or(""),
        "created_at=" + fields.get("created_at").unwrap_or(""),
      ].join("\n")
      self.store.set_string("issues/" + id + "/meta", meta)
      true
    }
    None => false
  }
}

// ---- Webhook Log ----

///|
pub struct WebhookLogEntry {
  id : String
  event_type : String
  source : String
  timestamp : String
  triggered : Int
}

///|
pub fn ApiState::log_webhook(
  self : ApiState,
  id : String,
  event_type : String,
  source : String,
  timestamp : String,
  triggered : Int,
) -> Unit {
  let meta = [
    "event_type=" + event_type,
    "source=" + source,
    "timestamp=" + timestamp,
    "triggered=" + triggered.to_string(),
  ].join("\n")
  self.store.set_string("webhooks/" + id, meta)
}

///|
pub fn ApiState::list_webhooks(self : ApiState) -> Array[WebhookLogEntry] {
  let ids = self.store.list("webhooks")
  let entries : Array[WebhookLogEntry] = []
  for id in ids {
    match self.store.get("webhooks/" + id) {
      Some(bytes) => {
        let fields = parse_kv_fields(@utf8.decode_lossy(bytes))
        entries.push({
          id,
          event_type: fields.get("event_type").unwrap_or(""),
          source: fields.get("source").unwrap_or(""),
          timestamp: fields.get("timestamp").unwrap_or(""),
          triggered: match fields.get("triggered") {
            Some(s) => parse_int_safe(s)
            None => 0
          },
        })
      }
      None => ()
    }
  }
  entries.sort_by(fn(a, b) { String::compare(b.timestamp, a.timestamp) })
  entries
}

///|
fn parse_int_safe(s : String) -> Int {
  let mut n = 0
  for c in s {
    if c >= '0' && c <= '9' {
      n = n * 10 + (c.to_int() - '0'.to_int())
    }
  }
  n
}

// ---- Pull Requests ----

///|
pub struct PullRequest {
  id : String
  title : String
  state : String // "open", "merged", "closed"
  author : String
  base_ref : String
  head_ref : String
  created_at : String
}

///|
pub struct PullRequestDetail {
  pr : PullRequest
  body : String
  compare : CompareResult?
}

///|
pub fn ApiState::create_pull_request(
  self : ApiState,
  title : String,
  body : String,
  author : String,
  base_ref : String,
  head_ref : String,
  timestamp : String,
) -> String {
  let existing = self.store.list("prs")
  let mut max_id = 0
  for id_str in existing {
    let n = parse_int_safe(id_str)
    if n > max_id {
      max_id = n
    }
  }
  let new_id = (max_id + 1).to_string()
  let meta = [
    "title=" + title,
    "state=open",
    "author=" + author,
    "base_ref=" + base_ref,
    "head_ref=" + head_ref,
    "created_at=" + timestamp,
  ].join("\n")
  self.store.set_string("prs/" + new_id + "/meta", meta)
  if body.length() > 0 {
    self.store.set_string("prs/" + new_id + "/body", body)
  }
  new_id
}

///|
pub fn ApiState::list_pull_requests(
  self : ApiState,
) -> Array[PullRequest] {
  let ids = self.store.list("prs")
  let entries : Array[PullRequest] = []
  for id in ids {
    match self.store.get("prs/" + id + "/meta") {
      Some(bytes) => {
        let fields = parse_kv_fields(@utf8.decode_lossy(bytes))
        entries.push({
          id,
          title: fields.get("title").unwrap_or(""),
          state: fields.get("state").unwrap_or("open"),
          author: fields.get("author").unwrap_or(""),
          base_ref: fields.get("base_ref").unwrap_or(""),
          head_ref: fields.get("head_ref").unwrap_or(""),
          created_at: fields.get("created_at").unwrap_or(""),
        })
      }
      None => ()
    }
  }
  entries.sort_by(fn(a, b) { String::compare(b.created_at, a.created_at) })
  entries
}

///|
pub fn ApiState::get_pull_request(
  self : ApiState,
  id : String,
) -> PullRequestDetail? {
  match self.store.get("prs/" + id + "/meta") {
    Some(bytes) => {
      let fields = parse_kv_fields(@utf8.decode_lossy(bytes))
      let pr : PullRequest = {
        id,
        title: fields.get("title").unwrap_or(""),
        state: fields.get("state").unwrap_or("open"),
        author: fields.get("author").unwrap_or(""),
        base_ref: fields.get("base_ref").unwrap_or(""),
        head_ref: fields.get("head_ref").unwrap_or(""),
        created_at: fields.get("created_at").unwrap_or(""),
      }
      let body = match self.store.get("prs/" + id + "/body") {
        Some(b) => @utf8.decode_lossy(b)
        None => ""
      }
      let compare = self.compare_commits(pr.base_ref, pr.head_ref)
      Some({ pr, body, compare })
    }
    None => None
  }
}

///|
pub fn ApiState::merge_pull_request(
  self : ApiState,
  id : String,
) -> Bool {
  match self.store.get("prs/" + id + "/meta") {
    Some(bytes) => {
      let fields = parse_kv_fields(@utf8.decode_lossy(bytes))
      let meta = [
        "title=" + fields.get("title").unwrap_or(""),
        "state=merged",
        "author=" + fields.get("author").unwrap_or(""),
        "base_ref=" + fields.get("base_ref").unwrap_or(""),
        "head_ref=" + fields.get("head_ref").unwrap_or(""),
        "created_at=" + fields.get("created_at").unwrap_or(""),
      ].join("\n")
      self.store.set_string("prs/" + id + "/meta", meta)
      true
    }
    None => false
  }
}

///|
pub fn ApiState::close_pull_request(
  self : ApiState,
  id : String,
) -> Bool {
  match self.store.get("prs/" + id + "/meta") {
    Some(bytes) => {
      let fields = parse_kv_fields(@utf8.decode_lossy(bytes))
      let meta = [
        "title=" + fields.get("title").unwrap_or(""),
        "state=closed",
        "author=" + fields.get("author").unwrap_or(""),
        "base_ref=" + fields.get("base_ref").unwrap_or(""),
        "head_ref=" + fields.get("head_ref").unwrap_or(""),
        "created_at=" + fields.get("created_at").unwrap_or(""),
      ].join("\n")
      self.store.set_string("prs/" + id + "/meta", meta)
      true
    }
    None => false
  }
}

// ---- File Edit ----

///|
pub struct FileEditResult {
  ok : Bool
  commit_sha : String
  error : String
}

///|
pub fn ApiState::edit_file(
  self : ApiState,
  path : String,
  content : String,
  message : String,
  author : String,
  timestamp : String,
) -> FileEditResult {
  if path.length() == 0 {
    return { ok: false, commit_sha: "", error: "empty path" }
  }
  if message.length() == 0 {
    return { ok: false, commit_sha: "", error: "empty commit message" }
  }
  // Write file to storage
  self.store.set_string(path, content)
  // Create a commit entry for this edit
  let commits = self.list_commits()
  let parent = if commits.length() > 0 { commits[0].sha } else { "" }
  let sha = "edit-" + timestamp + "-" + simple_hash(path + content)
  let meta = [
    "message=" + message,
    "author=" + author,
    "timestamp=" + timestamp,
    "parent=" + parent,
  ].join("\n")
  self.store.set_string("git/commits/" + sha, meta)
  // Record diff
  self.store.set_string(
    "git/diffs/" + sha + "/0",
    "path=" + path + "\nkind=modified\npatch=(edited via web)",
  )
  { ok: true, commit_sha: sha, error: "" }
}

///|
fn simple_hash(input : String) -> String {
  let mut h = 5381
  for c in input {
    h = h * 33 + c.to_int()
  }
  if h < 0 { h = -h }
  h.to_string()
}

// ---- Tags ----

///|
pub struct TagEntry {
  name : String
  sha : String
  message : String
}

///|
pub fn ApiState::list_tags(self : ApiState) -> Array[TagEntry] {
  let names = self.store.list("git/tags")
  let entries : Array[TagEntry] = []
  for name in names {
    match self.store.get("git/tags/" + name) {
      Some(bytes) => {
        let fields = parse_kv_fields(@utf8.decode_lossy(bytes))
        entries.push({
          name,
          sha: fields.get("sha").unwrap_or(""),
          message: fields.get("message").unwrap_or(""),
        })
      }
      None => ()
    }
  }
  entries.sort_by(fn(a, b) { String::compare(b.name, a.name) })
  entries
}

// ---- Stats ----

///|
pub struct RepoStats {
  file_count : Int
  commit_count : Int
  branch_count : Int
  issue_count : Int
  pr_count : Int
  contributors : Array[(String, Int)] // (author, commit_count)
}

///|
pub fn ApiState::repo_stats(self : ApiState) -> RepoStats {
  let commits = self.list_commits()
  let author_counts : Map[String, Int] = {}
  for commit in commits {
    let name = match commit.author.find(" <") {
      Some(i) => String::unsafe_substring(commit.author, start=0, end=i)
      None => commit.author
    }
    let current = author_counts.get(name).unwrap_or(0)
    author_counts.set(name, current + 1)
  }
  let contributors : Array[(String, Int)] = []
  for name, count in author_counts {
    contributors.push((name, count))
  }
  contributors.sort_by(fn(a, b) { b.1 - a.1 })
  // Count files recursively
  let file_count = count_files(self.store, "")
  {
    file_count,
    commit_count: commits.length(),
    branch_count: self.list_branches().length(),
    issue_count: self.list_issues().length(),
    pr_count: self.list_pull_requests().length(),
    contributors,
  }
}

///|
fn count_files(store : &Storage, prefix : String) -> Int {
  let mut count = 0
  let names = store.list(prefix)
  for name in names {
    let full = if prefix.length() == 0 { name } else { prefix + "/" + name }
    if store.has(full) {
      count += 1
    } else {
      count += count_files(store, full)
    }
  }
  count
}

// ---- PR Review Comments ----

///|
pub fn ApiState::add_pr_comment(
  self : ApiState,
  pr_id : String,
  author : String,
  body : String,
  timestamp : String,
) -> Bool {
  if self.store.get("prs/" + pr_id + "/meta") is None {
    return false
  }
  let existing = self.store.list("prs/" + pr_id + "/comments")
  let next_id = existing.length().to_string()
  let comment = [
    "author=" + author,
    "body=" + body,
    "created_at=" + timestamp,
  ].join("\n")
  self.store.set_string("prs/" + pr_id + "/comments/" + next_id, comment)
  true
}

///|
pub fn ApiState::list_pr_comments(
  self : ApiState,
  pr_id : String,
) -> Array[IssueComment] {
  let comment_ids = self.store.list("prs/" + pr_id + "/comments")
  let comments : Array[IssueComment] = []
  for cid in comment_ids {
    match self.store.get("prs/" + pr_id + "/comments/" + cid) {
      Some(cbytes) => {
        let cf = parse_kv_fields(@utf8.decode_lossy(cbytes))
        comments.push({
          author: cf.get("author").unwrap_or(""),
          body: cf.get("body").unwrap_or(""),
          created_at: cf.get("created_at").unwrap_or(""),
        })
      }
      None => ()
    }
  }
  comments
}

// ---- RSS Feed ----

///|
pub fn ApiState::activity_rss(
  self : ApiState,
  base_url : String,
) -> String {
  let events = self.activity_feed(limit=20)
  let sb = StringBuilder::new()
  sb.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
  sb.write_string("<rss version=\"2.0\">\n<channel>\n")
  sb.write_string("<title>bithub activity</title>\n")
  sb.write_string("<link>" + base_url + "</link>\n")
  sb.write_string("<description>Recent activity</description>\n")
  for event in events {
    let path = match event.kind {
      "commit" => "/commit/" + event.id
      "ci_run" => "/actions/runs/" + event.id
      "issue" => "/issues/" + event.id
      "pr" => "/pulls/" + event.id
      _ => "/"
    }
    let link = base_url + path
    sb.write_string("<item>\n")
    sb.write_string("<title>" + xml_escape(event.title) + "</title>\n")
    sb.write_string("<link>" + link + "</link>\n")
    sb.write_string(
      "<description>" + xml_escape(event.detail) + "</description>\n",
    )
    sb.write_string("<guid>" + link + "</guid>\n")
    sb.write_string("</item>\n")
  }
  sb.write_string("</channel>\n</rss>")
  sb.to_string()
}

///|
fn xml_escape(s : String) -> String {
  let sb = StringBuilder::new()
  for c in s {
    match c {
      '&' => sb.write_string("&amp;")
      '<' => sb.write_string("&lt;")
      '>' => sb.write_string("&gt;")
      '"' => sb.write_string("&quot;")
      _ => sb.write_char(c)
    }
  }
  sb.to_string()
}

// ---- Blame ----

///|
pub struct BlameLine {
  line_number : Int
  content : String
  commit_sha : String
  author : String
}

///|
pub fn ApiState::blame(
  self : ApiState,
  path : String,
) -> Array[BlameLine]? {
  // Get current file content
  let content = match self.file_text(path) {
    Some(c) => c
    None => return None
  }
  let lines : Array[String] = []
  for line_view in content.split("\n") {
    lines.push(line_view.to_string())
  }
  // Walk commits in reverse chronological order to find which commit
  // last touched each line. Simple approach: check if file changed in
  // each commit's diff.
  let commits = self.list_commits()
  let result : Array[BlameLine] = []
  // For each line, find the most recent commit that has a diff touching this file
  let file_commits : Array[CommitEntry] = []
  for commit in commits {
    match self.get_commit(commit.sha) {
      Some(detail) => {
        for df in detail.diff_files {
          if df.path == path {
            file_commits.push(commit)
            break
          }
        }
      }
      None => ()
    }
  }
  // Attribute: if we found commits that touched this file, use the most recent one
  // For a simple blame, assign all lines to the most recent touching commit,
  // or to the oldest commit if no diff info
  let default_commit = if file_commits.length() > 0 {
    file_commits[0]
  } else if commits.length() > 0 {
    commits[commits.length() - 1]
  } else {
    { sha: "unknown", message: "", author: "unknown", timestamp: "" }
  }
  for i in 0..<lines.length() {
    result.push({
      line_number: i + 1,
      content: lines[i],
      commit_sha: default_commit.sha,
      author: default_commit.author,
    })
  }
  Some(result)
}

// ---- Activity Feed ----

///|
pub struct ActivityEvent {
  kind : String // "commit", "ci_run", "issue"
  id : String
  title : String
  timestamp : String
  detail : String
}

///|
pub fn ApiState::activity_feed(
  self : ApiState,
  limit~ : Int = 20,
) -> Array[ActivityEvent] {
  let events : Array[ActivityEvent] = []
  // Commits
  for commit in self.list_commits() {
    let first_line = match commit.message.find("\n") {
      Some(i) => String::unsafe_substring(commit.message, start=0, end=i)
      None => commit.message
    }
    events.push({
      kind: "commit",
      id: commit.sha,
      title: first_line,
      timestamp: commit.timestamp,
      detail: commit.author,
    })
  }
  // CI runs
  for run in self.list_ci_runs() {
    events.push({
      kind: "ci_run",
      id: run.id,
      title: run.workflow_name + " [" + run.status + "]",
      timestamp: run.triggered_at,
      detail: "ref: " + run.ref_name,
    })
  }
  // Issues
  for issue in self.list_issues() {
    events.push({
      kind: "issue",
      id: issue.id,
      title: "#" + issue.id + " " + issue.title,
      timestamp: issue.created_at,
      detail: issue.author,
    })
  }
  // Pull requests
  for pr in self.list_pull_requests() {
    events.push({
      kind: "pr",
      id: pr.id,
      title: "PR #" + pr.id + " " + pr.title + " [" + pr.state + "]",
      timestamp: pr.created_at,
      detail: pr.author,
    })
  }
  events.sort_by(fn(a, b) { String::compare(b.timestamp, a.timestamp) })
  let result : Array[ActivityEvent] = []
  for i in 0..<events.length() {
    if i >= limit {
      break
    }
    result.push(events[i])
  }
  result
}

// ---- Compare (Branch Diff) ----

///|
pub struct CompareResult {
  base_sha : String
  head_sha : String
  commits : Array[CommitEntry]
  all_files : Array[DiffFileEntry]
}

///|
pub fn ApiState::compare_commits(
  self : ApiState,
  base_sha : String,
  head_sha : String,
) -> CompareResult? {
  // Walk from head back to base, collecting commits and diffs
  let commits : Array[CommitEntry] = []
  let all_files : Array[DiffFileEntry] = []
  let seen : Map[String, Bool] = {}
  let mut current = head_sha
  let mut found_base = false
  // Walk up to 100 commits to prevent infinite loops
  for i = 0; i < 100; i = i + 1 {
    if current.length() == 0 || current == base_sha {
      found_base = current == base_sha
      break
    }
    match self.get_commit(current) {
      Some(detail) => {
        commits.push(detail.commit)
        for df in detail.diff_files {
          if not(seen.contains(df.path)) {
            seen.set(df.path, true)
            all_files.push(df)
          }
        }
        current = detail.parent_sha
      }
      None => break
    }
  }
  if not(found_base) && commits.length() == 0 {
    return None
  }
  Some({ base_sha, head_sha, commits, all_files })
}
