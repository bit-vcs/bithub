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
