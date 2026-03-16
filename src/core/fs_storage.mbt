///| FsStorage: local filesystem-backed Storage implementation.
///  Keys map to files under a root directory.
///  Key "a/b/c" → root_dir/a/b/c
///  Requires Node.js (uses fs module via JS FFI).

///|
pub struct FsStorage {
  root : String
}

///|
pub fn FsStorage::new(root : String) -> FsStorage {
  fs_mkdir_p(root)
  { root, }
}

///|
fn fs_key_path(self : FsStorage, key : String) -> String {
  if self.root.has_suffix("/") {
    self.root + key
  } else {
    self.root + "/" + key
  }
}

///|
pub impl Storage for FsStorage with get(self, key) {
  match fs_read_bytes(self.fs_key_path(key)) {
    Some(bytes) => Some(bytes)
    None => None
  }
}

///|
pub impl Storage for FsStorage with set_string(self, key, value) {
  let path = self.fs_key_path(key)
  let dir = fs_parent(path)
  fs_mkdir_p(dir)
  fs_write_string(path, value)
}

///|
pub impl Storage for FsStorage with list(self, prefix) {
  let dir = if prefix.length() == 0 {
    self.root
  } else {
    self.fs_key_path(prefix)
  }
  fs_readdir(dir)
}

///|
pub impl Storage for FsStorage with has(self, key) {
  fs_is_file(self.fs_key_path(key))
}

// ---- JS FFI for Node.js fs operations ----

///|
extern "js" fn fs_read_bytes(path : String) -> Bytes? =
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
extern "js" fn fs_write_string(path : String, content : String) -> Unit =
  #| (path, content) => {
  #|   const fs = require("node:fs");
  #|   fs.writeFileSync(path, content, "utf-8");
  #| }

///|
extern "js" fn fs_readdir(path : String) -> Array[String] =
  #| (path) => {
  #|   try {
  #|     const fs = require("node:fs");
  #|     return fs.readdirSync(path).filter(n => !n.startsWith('.'));
  #|   } catch {
  #|     return [];
  #|   }
  #| }

///|
extern "js" fn fs_is_file(path : String) -> Bool =
  #| (path) => {
  #|   try {
  #|     const fs = require("node:fs");
  #|     return fs.statSync(path).isFile();
  #|   } catch {
  #|     return false;
  #|   }
  #| }

///|
extern "js" fn fs_mkdir_p(path : String) -> Unit =
  #| (path) => {
  #|   try {
  #|     const fs = require("node:fs");
  #|     fs.mkdirSync(path, { recursive: true });
  #|   } catch {}
  #| }

///|
extern "js" fn fs_parent(path : String) -> String =
  #| (path) => {
  #|   const idx = path.lastIndexOf('/');
  #|   return idx > 0 ? path.slice(0, idx) : '.';
  #| }
