///| Storage trait: abstract key-value backend for ApiState.
///  Implementations: MemoryStorage (in-memory, default),
///  and future R2Storage (Cloudflare R2), FsStorage (local filesystem), etc.
pub(open) trait Storage {
  /// Get a value by key. Returns None if not found.
  get(Self, String) -> Bytes?
  /// Set a value by key (UTF-8 string convenience).
  set_string(Self, String, String) -> Unit
  /// List child keys under a prefix (one level, not recursive).
  list(Self, String) -> Array[String]
  /// Check if a key exists as a leaf (has a value, not just children).
  has(Self, String) -> Bool
}

///| MemoryStorage wraps the existing @kv.Kv for in-memory use.
pub struct MemoryStorage {
  kv : @kv.Kv
}

///|
impl Storage for MemoryStorage with get(self, key) {
  self.kv.get(key)
}

///|
impl Storage for MemoryStorage with set_string(self, key, value) {
  self.kv.set_string(key, value)
}

///|
impl Storage for MemoryStorage with list(self, prefix) {
  self.kv.list(prefix)
}

///|
impl Storage for MemoryStorage with has(self, key) {
  self.kv.has(key)
}

///| Create a MemoryStorage with seeded demo data.
pub fn MemoryStorage::new_seeded() -> MemoryStorage {
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
  let mem : MemoryStorage = { kv, }
  seed_files(mem)
  mem
}

///| MapStorage: simple in-memory Map-based storage (no bit/kv dependency).
///  Useful for testing and lightweight deployments.
pub struct MapStorage {
  data : Map[String, String]
}

///|
pub fn MapStorage::new() -> MapStorage {
  { data: {} }
}

///|
pub impl Storage for MapStorage with get(self, key) {
  match self.data.get(key) {
    Some(v) => Some(@utf8.encode(v))
    None => None
  }
}

///|
pub impl Storage for MapStorage with set_string(self, key, value) {
  self.data.set(key, value)
}

///|
pub impl Storage for MapStorage with list(self, prefix) {
  let result : Array[String] = []
  let seen : Map[String, Bool] = {}
  let prefix_with_slash = if prefix.length() == 0 {
    ""
  } else {
    prefix + "/"
  }
  for key, _ in self.data {
    if prefix_with_slash.length() == 0 || key.has_prefix(prefix_with_slash) {
      let rest = String::unsafe_substring(
        key,
        start=prefix_with_slash.length(),
        end=key.length(),
      )
      if rest.length() == 0 {
        continue
      }
      let name = match rest.find("/") {
        Some(i) => String::unsafe_substring(rest, start=0, end=i)
        None => rest
      }
      if !seen.contains(name) {
        seen.set(name, true)
        result.push(name)
      }
    }
  }
  result
}

///|
pub impl Storage for MapStorage with has(self, key) {
  self.data.contains(key)
}

///|
fn parse_kv_fields(text : String) -> Map[String, String] {
  let fields : Map[String, String] = {}
  for line_view in text.split("\n") {
    let line = line_view.to_string()
    if line.length() == 0 {
      continue
    }
    match line.find("=") {
      Some(i) => {
        let key = String::unsafe_substring(line, start=0, end=i)
        let value = String::unsafe_substring(
          line,
          start=i + 1,
          end=line.length(),
        )
        fields.set(key, value)
      }
      None => ()
    }
  }
  fields
}