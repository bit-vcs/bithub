///| Benchmarks for bithub local viewer

///| run: moon bench -p bit-vcs/bithub/cmd/bithub --target js -f bench_viewer_test.mbt

///|
let bench_state : RepoState = RepoState::new(".")

///|
test "bench scan_repo_files" (b : @bench.T) {
  b.bench(fn() {
    let files = scan_repo_files(".", 240)
    b.keep(files.length())
  })
}

///|
test "bench load_repo_issues" (b : @bench.T) {
  b.bench(fn() {
    let issues = load_repo_issues(".", 120)
    b.keep(issues.length())
  })
}

///|
test "bench render_root" (b : @bench.T) {
  b.bench(fn() {
    let res = bench_state.render_root()
    b.keep(res.html.length())
  })
}

///|
test "bench render_issues" (b : @bench.T) {
  b.bench(fn() {
    let res = bench_state.render_issues()
    b.keep(res.html.length())
  })
}
