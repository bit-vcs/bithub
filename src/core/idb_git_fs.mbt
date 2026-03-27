///| IndexedDB-backed git filesystem for browser-side git operations.
///  Uses a global JS cache (preloaded from IndexedDB) for synchronous access,
///  same pattern as R2Storage.

///|
pub struct IdbGitFs {
  prefix : String // e.g. "repo:" to namespace keys
}

///|
pub fn IdbGitFs::new(prefix? : String = "repo:") -> IdbGitFs {
  { prefix, }
}

///|
extern "js" fn idb_fs_get(prefix : String, key : String) -> Bytes? =
  #| (() => {
  #|   return (prefix, key) => {
  #|     const cache = globalThis.__idb_fs_cache || {};
  #|     const val = cache[prefix + key];
  #|     if (val === undefined) return undefined;
  #|     if (val instanceof Uint8Array) return val;
  #|     // String → Bytes
  #|     return new TextEncoder().encode(val);
  #|   };
  #| })()

///|
extern "js" fn idb_fs_put_bytes(
  prefix : String,
  key : String,
  value : Bytes,
) -> Unit =
  #| (() => {
  #|   return (prefix, key, value) => {
  #|     if (!globalThis.__idb_fs_cache) globalThis.__idb_fs_cache = {};
  #|     globalThis.__idb_fs_cache[prefix + key] = value;
  #|     if (!globalThis.__idb_fs_dirty) globalThis.__idb_fs_dirty = {};
  #|     globalThis.__idb_fs_dirty[prefix + key] = true;
  #|   };
  #| })()

///|
extern "js" fn idb_fs_put_string(
  prefix : String,
  key : String,
  value : String,
) -> Unit =
  #| (() => {
  #|   return (prefix, key, value) => {
  #|     if (!globalThis.__idb_fs_cache) globalThis.__idb_fs_cache = {};
  #|     globalThis.__idb_fs_cache[prefix + key] = value;
  #|     if (!globalThis.__idb_fs_dirty) globalThis.__idb_fs_dirty = {};
  #|     globalThis.__idb_fs_dirty[prefix + key] = true;
  #|   };
  #| })()

///|
extern "js" fn idb_fs_has(prefix : String, key : String) -> Bool =
  #| (() => {
  #|   return (prefix, key) => {
  #|     const cache = globalThis.__idb_fs_cache || {};
  #|     return (prefix + key) in cache;
  #|   };
  #| })()

///|
extern "js" fn idb_fs_list(
  prefix : String,
  dir : String,
) -> Array[String] =
  #| (() => {
  #|   return (prefix, dir) => {
  #|     const cache = globalThis.__idb_fs_cache || {};
  #|     const fullPrefix = prefix + (dir.endsWith('/') ? dir : dir + '/');
  #|     const seen = new Set();
  #|     for (const k of Object.keys(cache)) {
  #|       if (!k.startsWith(fullPrefix)) continue;
  #|       const rest = k.slice(fullPrefix.length);
  #|       const slash = rest.indexOf('/');
  #|       seen.add(slash >= 0 ? rest.slice(0, slash) : rest);
  #|     }
  #|     return Array.from(seen);
  #|   };
  #| })()

///|
extern "js" fn idb_fs_is_dir(prefix : String, path : String) -> Bool =
  #| (() => {
  #|   return (prefix, path) => {
  #|     const cache = globalThis.__idb_fs_cache || {};
  #|     const dirPrefix = prefix + path + '/';
  #|     for (const k of Object.keys(cache)) {
  #|       if (k.startsWith(dirPrefix)) return true;
  #|     }
  #|     return false;
  #|   };
  #| })()

///|
extern "js" fn idb_fs_remove(prefix : String, key : String) -> Unit =
  #| (() => {
  #|   return (prefix, key) => {
  #|     if (globalThis.__idb_fs_cache) delete globalThis.__idb_fs_cache[prefix + key];
  #|     if (!globalThis.__idb_fs_dirty) globalThis.__idb_fs_dirty = {};
  #|     globalThis.__idb_fs_dirty[prefix + key] = '__deleted__';
  #|   };
  #| })()

///| FileSystem trait: write operations
pub impl @bit.FileSystem for IdbGitFs with mkdir_p(_self, _path) {
  // Dirs are implicit in key structure
}

///|
pub impl @bit.FileSystem for IdbGitFs with write_file(self, path, data) {
  idb_fs_put_bytes(self.prefix, path, data)
}

///|
pub impl @bit.FileSystem for IdbGitFs with write_string(self, path, data) {
  idb_fs_put_string(self.prefix, path, data)
}

///|
pub impl @bit.FileSystem for IdbGitFs with remove_file(self, path) {
  idb_fs_remove(self.prefix, path)
}

///|
pub impl @bit.FileSystem for IdbGitFs with remove_dir(_self, _path) {
  // No-op: dirs are implicit
}

///| RepoFileSystem trait: read operations
pub impl @bit.RepoFileSystem for IdbGitFs with read_file(self, path) {
  match idb_fs_get(self.prefix, path) {
    Some(data) => data
    None => raise @bit.GitError::IoError("not found: " + path)
  }
}

///|
pub impl @bit.RepoFileSystem for IdbGitFs with readdir(self, path) {
  idb_fs_list(self.prefix, path)
}

///|
pub impl @bit.RepoFileSystem for IdbGitFs with is_dir(self, path) {
  idb_fs_is_dir(self.prefix, path)
}

///|
pub impl @bit.RepoFileSystem for IdbGitFs with is_file(self, path) {
  idb_fs_has(self.prefix, path)
}
