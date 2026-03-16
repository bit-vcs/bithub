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
  kv : @kv.Kv
}

///|
pub fn ApiState::new() -> ApiState {
  let fs = @bit.TestFs::new()
  let bit_fs = @bitfs.Fs::empty("/repo/.git")
  let tree : KvWorkingTree = { fs: bit_fs, backing_fs: fs, write_fs: fs }
  let store : KvObjectStore = {
    backing_fs: fs,
    write_fs: fs,
    git_dir: "/repo/.git",
  }
  let kv = @kv.Kv::new(
    @kv.NodeId::new("bithub"),
    tree,
    store,
    @bit.ObjectId::zero(),
  )
  seed_files(kv)
  { kv, }
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
  let names = self.kv.list(path)
  names.sort_by(fn(a, b) { String::compare(a, b) })
  let entries : Array[FileEntry] = []
  for name in names {
    let full_path = join_path(path, name)
    entries.push({ name, path: full_path, is_dir: not(self.kv.has(full_path)) })
  }
  entries
}

///|
pub fn ApiState::file_text(self : ApiState, raw_path : String) -> String? {
  let path = normalize_path(raw_path)
  match self.kv.get(path) {
    Some(bytes) => Some(@utf8.decode_lossy(bytes))
    None => None
  }
}

///|
fn seed_files(kv : @kv.Kv) -> Unit {
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
  let shas = self.kv.list("git/commits")
  let entries : Array[CommitEntry] = []
  for sha in shas {
    match self.kv.get("git/commits/" + sha) {
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
  match self.kv.get("git/commits/" + sha) {
    Some(bytes) => {
      let text = @utf8.decode_lossy(bytes)
      match parse_commit_entry(text, sha) {
        Some(commit) => {
          let fields = parse_kv_fields(text)
          let parent = fields.get("parent").unwrap_or("")
          let diff_files : Array[DiffFileEntry] = []
          let diff_keys = self.kv.list("git/diffs/" + sha)
          for dk in diff_keys {
            match self.kv.get("git/diffs/" + sha + "/" + dk) {
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
  let names = self.kv.list("git/branches")
  let entries : Array[BranchEntry] = []
  for name in names {
    match self.kv.get("git/branches/" + name) {
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
  let names = self.kv.list(workflow_dir)
  names.sort_by(fn(a, b) { String::compare(a, b) })
  for name in names {
    let path = workflow_dir + "/" + name
    if not(name.has_suffix(".yml") || name.has_suffix(".yaml")) {
      continue
    }
    match self.kv.get(path) {
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
  match self.kv.get(path) {
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
