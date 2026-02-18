///|
pub fn load_repo_issues(root : String, limit : Int) -> Array[IssueSummary] {
  let git_dir = @npath.join2(root, ".git")
  if not(@nfs.existsSync(git_dir)) {
    return []
  }
  let os_fs = JsOsFs::new()
  let objects : HubObjectStore = { fs: os_fs, rfs: os_fs, git_dir }
  let refs : HubRefStore = { fs: os_fs, rfs: os_fs, git_dir }
  let hub = @hub.Hub::load(objects, refs) catch { _ => return [] }
  let issues = hub.list_issues(objects)
  let result : Array[IssueSummary] = []
  for issue in issues {
    if result.length() < limit {
      result.push(
        issue_summary(issue.id(), issue.title(), issue.state().to_string()),
      )
    }
  }
  result
}

///|
priv struct JsOsFs {
  _dummy : Int
}

///|
fn JsOsFs::new() -> JsOsFs {
  { _dummy: 0 }
}

///|
fn io_error(err : @fs.IOError) -> @bit.GitError {
  @bit.GitError::IoError(err.to_string())
}

///|
fn ensure_dir(path : String) -> Unit raise @bit.GitError {
  let is_dir = @fs.is_dir(path) catch { _ => false }
  if is_dir {
    return
  }
  let parts = path.split("/").collect()
  let mut current = ""
  for part_view in parts {
    let part = part_view.to_string()
    if part.length() == 0 {
      current = "/"
      continue
    }
    current = if current.length() == 0 || current == "/" {
      current + part
    } else {
      current + "/" + part
    }
    let exists = @fs.is_dir(current) catch { _ => false }
    if not(exists) {
      @fs.create_dir(current) catch {
        err => raise io_error(err)
      }
    }
  }
}

///|
impl @bit.FileSystem for JsOsFs with mkdir_p(_self, path) {
  ensure_dir(path)
}

///|
impl @bit.FileSystem for JsOsFs with write_file(_self, path, content) {
  @fs.write_bytes_to_file(path, content) catch {
    err => raise io_error(err)
  }
}

///|
impl @bit.FileSystem for JsOsFs with write_string(_self, path, content) {
  @fs.write_string_to_file(path, content) catch {
    err => raise io_error(err)
  }
}

///|
impl @bit.FileSystem for JsOsFs with remove_file(_self, path) {
  @fs.remove_file(path) catch {
    err => raise io_error(err)
  }
}

///|
impl @bit.FileSystem for JsOsFs with remove_dir(_self, path) {
  @fs.remove_dir(path) catch {
    err => raise io_error(err)
  }
}

///|
impl @bit.RepoFileSystem for JsOsFs with read_file(_self, path) {
  @fs.read_file_to_bytes(path) catch {
    err => raise io_error(err)
  }
}

///|
impl @bit.RepoFileSystem for JsOsFs with readdir(_self, path) {
  @fs.read_dir(path) catch {
    err => raise io_error(err)
  }
}

///|
impl @bit.RepoFileSystem for JsOsFs with is_dir(_self, path) {
  @fs.is_dir(path) catch {
    _ => false
  }
}

///|
impl @bit.RepoFileSystem for JsOsFs with is_file(_self, path) {
  @fs.is_file(path) catch {
    _ => false
  }
}

///|
priv struct HubObjectStore {
  fs : &@bit.FileSystem
  rfs : &@bit.RepoFileSystem
  git_dir : String
}

///|
impl @bitlib.ObjectStore for HubObjectStore with get(self, id) {
  let db = @bitlib.ObjectDb::load_lazy(self.rfs, self.git_dir)
  db.get(self.rfs, id)
}

///|
impl @bitlib.ObjectStore for HubObjectStore with put(self, obj_type, data) {
  @bitlib.write_loose_object(self.fs, self.git_dir, obj_type, data)
}

///|
impl @bitlib.ObjectStore for HubObjectStore with has(self, id) {
  let db = @bitlib.ObjectDb::load_lazy(self.rfs, self.git_dir) catch {
    _ => return false
  }
  let obj = db.get(self.rfs, id) catch { _ => return false }
  obj is Some(_)
}

///|
priv struct HubRefStore {
  fs : &@bit.FileSystem
  rfs : &@bit.RepoFileSystem
  git_dir : String
}

///|
impl @bitlib.RefStore for HubRefStore with resolve(self, ref_name) {
  @bitlib.resolve_ref(self.rfs, self.git_dir, ref_name)
}

///|
impl @bitlib.RefStore for HubRefStore with update(self, ref_name, id) {
  match id {
    Some(commit_id) => {
      let ref_path = join_path(self.git_dir, ref_name)
      let dir = parent_path(ref_path)
      self.fs.mkdir_p(dir)
      self.fs.write_string(ref_path, commit_id.to_hex() + "\n")
    }
    None => ()
  }
}

///|
impl @bitlib.RefStore for HubRefStore with list(self, _prefix) {
  ignore(self)
  []
}

///|
fn join_path(a : String, b : String) -> String {
  if a.has_suffix("/") {
    a + b
  } else {
    a + "/" + b
  }
}

///|
fn parent_path(path : String) -> String {
  match path.rev_find("/") {
    None => "."
    Some(0) => "."
    Some(idx) => String::unsafe_substring(path, start=0, end=idx)
  }
}
