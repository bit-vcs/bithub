///|
pub fn scan_repo_files(root : String, limit : Int) -> Array[String] {
  let out : Array[String] = []
  scan_repo_files_recursive(root, "", out, limit)
  out.sort_by(fn(a, b) { String::compare(a, b) })
  out
}

///|
pub fn load_repo_file(root : String, rel_path : String) -> String? {
  let abs_path = @npath.join2(root, rel_path)
  let text = @nfs.read_file_as_string(abs_path, encoding="utf-8") catch {
    _ => return None
  }
  Some(text)
}

///|
priv enum EntryKind {
  Dir
  File
  Other
}

///|
fn path_kind(abs_path : String) -> EntryKind {
  let st = @nfs.stat_sync(abs_path) catch { _ => return Other }
  if st.isDirectory() {
    Dir
  } else if st.isFile() {
    File
  } else {
    Other
  }
}

///|
fn scan_repo_files_recursive(
  root : String,
  rel_dir : String,
  out : Array[String],
  limit : Int,
) -> Unit {
  if out.length() >= limit {
    return
  }
  let abs_dir = if rel_dir.length() == 0 {
    root
  } else {
    @npath.join2(root, rel_dir)
  }
  let names = @nfs.readdir_sync(abs_dir) catch { _ => [] }
  names.sort_by(fn(a, b) { String::compare(a, b) })
  for name in names {
    if out.length() >= limit {
      return
    }
    if not(should_skip_name(name)) {
      let rel_path = if rel_dir.length() == 0 {
        name
      } else {
        rel_dir + "/" + name
      }
      let abs_path = @npath.join2(root, rel_path)
      match path_kind(abs_path) {
        Dir => scan_repo_files_recursive(root, rel_path, out, limit)
        File => if is_viewable_file(rel_path) { out.push(rel_path) }
        Other => ()
      }
    }
  }
}

///|
fn should_skip_name(name : String) -> Bool {
  name == ".git" ||
  name == ".mooncakes" ||
  name == "_build" ||
  name == "target" ||
  name == "node_modules"
}

///|
fn is_viewable_file(path : String) -> Bool {
  if path.has_suffix(".png") ||
    path.has_suffix(".jpg") ||
    path.has_suffix(".jpeg") ||
    path.has_suffix(".gif") ||
    path.has_suffix(".webp") ||
    path.has_suffix(".wasm") {
    return false
  }
  true
}
