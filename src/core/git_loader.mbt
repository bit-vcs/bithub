///| Load real git repository data into Storage.
///  This module provides functions to populate a Storage backend
///  with data from an actual git repository, using bitlib.

///|
pub fn load_git_commits_into_storage(
  store : &Storage,
  fs : &@bit.RepoFileSystem,
  git_dir : String,
  max_count~ : Int = 50,
) -> Unit {
  let entries = @bitlib.log_head(
    fs,
    git_dir,
    max_count~,
  ) catch {
    _ => {
      println("load_git_commits: failed to read git log")
      return
    }
  }
  let mut prev_sha = ""
  // entries are newest-first; we need to set parent links
  for i = 0; i < entries.length(); i = i + 1 {
    let entry = entries[i]
    let sha = entry.id.to_hex()
    let parent = if i + 1 < entries.length() {
      entries[i + 1].id.to_hex()
    } else {
      ""
    }
    let meta = [
      "message=" + entry.message,
      "author=" + entry.author,
      "timestamp=" + entry.timestamp.to_string(),
      "parent=" + parent,
    ].join("\n")
    store.set_string("git/commits/" + sha, meta)
    prev_sha = sha
  }
  ignore(prev_sha)
}

///|
pub fn load_git_branches_into_storage(
  store : &Storage,
  fs : &@bit.RepoFileSystem,
  git_dir : String,
) -> Unit {
  let (head_ref, branches) = @bitlib.list_branches(fs, git_dir) catch {
    _ => {
      println("load_git_branches: failed to list branches")
      return
    }
  }
  let head_branch = match head_ref {
    Branch(name) => name
    _ => ""
  }
  for branch in branches {
    // Use -- as separator for / in branch names (KV path limitation)
    let safe_name = branch.name.replace(old="/", new="--")
    let meta = [
      "sha=" + branch.id.to_hex(),
      "current=" + (branch.name == head_branch).to_string(),
      "name=" + branch.name,
    ].join("\n")
    store.set_string("git/branches/" + safe_name, meta)
  }
}

///|
pub fn load_files_into_storage(
  store : &Storage,
  root : String,
  files : Array[String],
) -> Unit {
  for file_path in files {
    let full_path = if root.has_suffix("/") {
      root + file_path
    } else {
      root + "/" + file_path
    }
    match read_file_string(full_path) {
      Some(content) => store.set_string(file_path, content)
      None => ()
    }
  }
}

///|
pub fn write_file_and_commit(
  full_path : String,
  content : String,
  message : String,
  author : String,
) -> Unit {
  write_file_to_disk(full_path, content)
  let dir = parent_dir(full_path)
  git_exec(dir, "git add " + full_path)
  let author_arg = if author.length() > 0 && not(author.contains("<")) {
    " --author=\"" + author + " <" + author + "@bithub>\""
  } else if author.length() > 0 {
    " --author=\"" + author + "\""
  } else {
    ""
  }
  git_exec(dir, "git commit -m \"" + message + "\"" + author_arg + " --allow-empty")
}

///|
pub fn git_head_sha(repo_root : String) -> String? {
  git_head_sha_ffi(repo_root)
}

///|
extern "js" fn git_head_sha_ffi(repo_root : String) -> String? =
  #| (root) => {
  #|   try {
  #|     const { execSync } = require("node:child_process");
  #|     return execSync("git rev-parse HEAD", { cwd: root, encoding: "utf-8" }).trim();
  #|   } catch { return undefined; }
  #| }

///|
extern "js" fn write_file_to_disk(path : String, content : String) -> Unit =
  #| (path, content) => {
  #|   const fs = require("node:fs");
  #|   const dir = require("node:path").dirname(path);
  #|   fs.mkdirSync(dir, { recursive: true });
  #|   fs.writeFileSync(path, content, "utf-8");
  #| }

///|
extern "js" fn git_exec(cwd : String, cmd : String) -> Unit =
  #| (cwd, cmd) => {
  #|   try {
  #|     const { execSync } = require("node:child_process");
  #|     execSync(cmd, { cwd, timeout: 10000, stdio: "ignore" });
  #|   } catch {}
  #| }

///|
extern "js" fn parent_dir(path : String) -> String =
  #| (path) => require("node:path").dirname(path)

///|
pub fn load_workflow_files(store : &Storage, root : String) -> Unit {
  let wf_dir = root + "/.github/workflows"
  let files = scan_readdir(wf_dir)
  for name in files {
    if name.has_suffix(".yml") || name.has_suffix(".yaml") {
      match read_file_string(wf_dir + "/" + name) {
        Some(content) =>
          store.set_string(".github/workflows/" + name, content)
        None => ()
      }
    }
  }
}

///|
pub fn load_git_tags_into_storage(
  store : &Storage,
  _fs : &@bit.RepoFileSystem,
  git_dir : String,
) -> Unit {
  let tag_dir = git_dir + "/refs/tags"
  let names = scan_readdir(tag_dir)
  for name in names {
    match read_file_string(tag_dir + "/" + name) {
      Some(sha_raw) => {
        let sha = sha_raw.trim_start(chars=" \n\r\t").trim_end(chars=" \n\r\t").to_string()
        store.set_string("git/tags/" + name, "sha=" + sha + "\nmessage=" + name)
      }
      None => ()
    }
  }
}

///|
extern "js" fn read_file_string(path : String) -> String? =
  #| (path) => {
  #|   try {
  #|     const fs = require("node:fs");
  #|     return fs.readFileSync(path, "utf-8");
  #|   } catch {
  #|     return undefined;
  #|   }
  #| }

// ---- Node.js RepoFileSystem adapter ----

///|
/// NodeFs: implements @bit.RepoFileSystem using Node.js fs module.
/// Allows bitlib to read real git repositories from disk.
pub struct NodeFs {
  _dummy : Int
}

///|
pub fn NodeFs::new() -> NodeFs {
  { _dummy: 0 }
}

///|
impl @bit.RepoFileSystem for NodeFs with read_file(_self, path) {
  match node_read_file_safe(path) {
    Some(bytes) => bytes
    None => raise @bit.GitError::IoError("read_file failed: " + path)
  }
}

///|
impl @bit.RepoFileSystem for NodeFs with readdir(_self, path) {
  node_readdir_safe(path)
}

///|
impl @bit.RepoFileSystem for NodeFs with is_dir(_self, path) {
  node_is_dir(path)
}

///|
impl @bit.RepoFileSystem for NodeFs with is_file(_self, path) {
  node_is_file(path)
}

///|
extern "js" fn node_read_file_safe(path : String) -> Bytes? =
  #| (path) => {
  #|   try {
  #|     const fs = require("node:fs");
  #|     const buf = fs.readFileSync(path);
  #|     return new Uint8Array(buf);
  #|   } catch {
  #|     return undefined;
  #|   }
  #| }

///|
extern "js" fn node_readdir_safe(path : String) -> Array[String] =
  #| (path) => {
  #|   try {
  #|     const fs = require("node:fs");
  #|     return fs.readdirSync(path);
  #|   } catch {
  #|     return [];
  #|   }
  #| }

///|
extern "js" fn node_is_dir(path : String) -> Bool =
  #| (path) => {
  #|   try {
  #|     const fs = require("node:fs");
  #|     return fs.statSync(path).isDirectory();
  #|   } catch { return false; }
  #| }

///|
extern "js" fn node_is_file(path : String) -> Bool =
  #| (path) => {
  #|   try {
  #|     const fs = require("node:fs");
  #|     return fs.statSync(path).isFile();
  #|   } catch { return false; }
  #| }

///|
extern "js" fn scan_readdir(path : String) -> Array[String] =
  #| (path) => {
  #|   try {
  #|     const fs = require("node:fs");
  #|     return fs.readdirSync(path);
  #|   } catch {
  #|     return [];
  #|   }
  #| }

///|
/// Scan files in a directory recursively, skipping common non-source dirs.
pub fn scan_files(root : String, limit~ : Int = 200) -> Array[String] {
  let files : Array[String] = []
  scan_files_recursive(root, "", files, limit)
  files
}

///|
fn scan_files_recursive(
  root : String,
  prefix : String,
  files : Array[String],
  limit : Int,
) -> Unit {
  if files.length() >= limit {
    return
  }
  let dir = if prefix.length() == 0 { root } else { root + "/" + prefix }
  let entries = scan_readdir(dir)
  entries.sort_by(fn(a, b) { String::compare(a, b) })
  for name in entries {
    if files.length() >= limit {
      return
    }
    if name.has_prefix(".") ||
      name == "node_modules" ||
      name == "_build" ||
      name == ".mooncakes" ||
      name == "target" {
      continue
    }
    let rel = if prefix.length() == 0 { name } else { prefix + "/" + name }
    let full = root + "/" + rel
    if node_is_file(full) {
      files.push(rel)
    } else if node_is_dir(full) {
      scan_files_recursive(root, rel, files, limit)
    }
  }
}

///|
/// Load issues from relay API poll response into Storage.
/// `envelopes_json` is the full poll response JSON string.
pub fn load_relay_issues_into_storage(
  store : &Storage,
  envelopes_json : String,
) -> Int {
  let parsed = try { @json.parse(envelopes_json) } catch { _ => return 0 }
  let top = match parsed {
    Object(obj) => obj
    _ => return 0
  }
  let arr = match top.get("envelopes") {
    Some(Array(items)) => items
    _ => return 0
  }
  let mut count = 0
  for item in arr {
    let envelope = match item {
      Object(obj) => obj
      _ => continue
    }
    let payload = match envelope.get("payload") {
      Some(Object(p)) => p
      _ => continue
    }
    let kind = match payload.get("kind") {
      Some(String(k)) => k
      _ => continue
    }
    if kind != "hub.record" {
      continue
    }
    let record_str = match payload.get("record") {
      Some(String(r)) => r
      _ => continue
    }
    // Parse hub record → WorkItem → Issue
    let record = @hub.parse_hub_record(record_str)
    let work_item = @hub.parse_work_item(record.payload) catch { _ => continue }
    let issue = match work_item.to_issue() {
      Some(i) => i
      None => continue
    }
    let id = issue.id
    let state_str = match issue.state {
      @hub.IssueState::Open => "open"
      @hub.IssueState::Closed => "closed"
    }
    let meta = [
      "title=" + issue.title,
      "state=" + state_str,
      "author=" + issue.author,
      "created_at=" + issue.created_at.to_string(),
    ].join("\n")
    store.set_string("issues/" + id + "/meta", meta)
    if issue.body.length() > 0 {
      store.set_string("issues/" + id + "/body", issue.body)
    }
    if issue.labels.length() > 0 {
      store.set_string("issues/" + id + "/labels", issue.labels.join(","))
    }
    count += 1
  }
  count
}
