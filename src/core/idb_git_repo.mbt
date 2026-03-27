///| Browser-side git repository backed by IdbGitFs.
///  Provides init, add, commit, status operations using bitlib.

///|
pub struct IdbGitRepo {
  fs : IdbGitFs
  root : String // virtual root path, e.g. "/workspace"
  git_dir : String // e.g. "/workspace/.git"
}

///|
pub fn IdbGitRepo::new(workspace? : String = "/workspace") -> IdbGitRepo {
  let fs = IdbGitFs::new()
  { fs, root: workspace, git_dir: workspace + "/.git" }
}

///|
pub fn IdbGitRepo::init(self : IdbGitRepo) -> Unit raise @bit.GitError {
  let fs : &@bit.FileSystem = self.fs
  let rfs : &@bit.RepoFileSystem = self.fs
  ignore(rfs)
  fs.mkdir_p(self.git_dir + "/objects")
  fs.mkdir_p(self.git_dir + "/objects/pack")
  fs.mkdir_p(self.git_dir + "/refs/heads")
  fs.mkdir_p(self.git_dir + "/refs/tags")
  fs.write_string(self.git_dir + "/HEAD", "ref: refs/heads/main\n")
}

///|
pub fn IdbGitRepo::write_file(
  self : IdbGitRepo,
  path : String,
  content : String,
) -> Unit raise @bit.GitError {
  let fs : &@bit.FileSystem = self.fs
  let full = self.root + "/" + path
  fs.write_string(full, content)
}

///|
pub fn IdbGitRepo::read_file(
  self : IdbGitRepo,
  path : String,
) -> String? {
  let full = self.root + "/" + path
  match idb_fs_get(self.fs.prefix, full) {
    Some(data) => Some(@utf8.decode_lossy(data[:]))
    None => None
  }
}

///|
pub fn IdbGitRepo::add_and_commit(
  self : IdbGitRepo,
  paths : Array[String],
  message : String,
  author : String,
) -> @bit.ObjectId raise @bit.GitError {
  let fs : &@bit.FileSystem = self.fs
  let rfs : &@bit.RepoFileSystem = self.fs
  @bitlib.add_paths(fs, rfs, self.root, paths)
  let timestamp = idb_now_epoch()
  @bitlib.commit(
    fs,
    rfs,
    self.root,
    message,
    author,
    timestamp,
  )
}

///|
pub fn IdbGitRepo::head_commit(self : IdbGitRepo) -> @bit.ObjectId? {
  let rfs : &@bit.RepoFileSystem = self.fs
  @bitlib.resolve_head_commit(rfs, self.git_dir) catch { _ => None }
}

///|
extern "js" fn idb_now_epoch() -> Int64 =
  #| () => BigInt(Math.floor(Date.now() / 1000))
