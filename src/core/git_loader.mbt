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
  ) catch { _ => return }
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
    _ => return
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
extern "js" fn read_file_string(path : String) -> String? =
  #| (path) => {
  #|   try {
  #|     const fs = require("node:fs");
  #|     return fs.readFileSync(path, "utf-8");
  #|   } catch {
  #|     return undefined;
  #|   }
  #| }
