///|
struct BenchResult {
  name : String
  iterations : Int
  min_ms : Int
  max_ms : Int
  avg_ms : Int
  total_ms : Int
}

///|
fn parse_iterations(raw : String) -> Int {
  let parsed = @strconv.parse_int(raw) catch { _ => 20 }
  if parsed > 0 {
    parsed
  } else {
    20
  }
}

///|
fn parse_bench_args() -> (String, Int) {
  let argv = @nprocess.argv()
  let repo = if argv.length() > 2 { argv[2] } else { "." }
  let iterations = if argv.length() > 3 {
    parse_iterations(argv[3])
  } else {
    20
  }
  (repo, iterations)
}

///|
fn run_bench(name : String, iterations : Int, task : () -> Unit) -> BenchResult {
  let mut min_ms = 0
  let mut max_ms = 0
  let mut total_ms = 0
  for i in 0..<iterations {
    let start = @jdate.Date::now()
    task()
    let elapsed = @jdate.Date::now() - start
    if i == 0 {
      min_ms = elapsed
      max_ms = elapsed
    } else {
      if elapsed < min_ms {
        min_ms = elapsed
      }
      if elapsed > max_ms {
        max_ms = elapsed
      }
    }
    total_ms += elapsed
  }
  { name, iterations, min_ms, max_ms, avg_ms: total_ms / iterations, total_ms }
}

///|
fn print_result(result : BenchResult) -> Unit {
  println(
    "\{result.name}: n=\{result.iterations} min=\{result.min_ms}ms avg=\{result.avg_ms}ms max=\{result.max_ms}ms total=\{result.total_ms}ms",
  )
}

///|
fn main {
  let (repo, iterations) = parse_bench_args()
  println("bithub benchmark")
  println("repo: \{repo}")
  println("iterations: \{iterations}")

  let repo_state_new = run_bench("RepoState::new", iterations, fn() {
    ignore(@bithub.RepoState::new(repo))
  })
  let scan_files = run_bench("scan_repo_files", iterations, fn() {
    ignore(@bithub.scan_repo_files(repo, 240))
  })
  let load_issues = run_bench("load_repo_issues", iterations, fn() {
    ignore(@bithub.load_repo_issues(repo, 120))
  })

  let state = @bithub.RepoState::new(repo)
  let render_root = run_bench("RepoState::render_root", iterations, fn() {
    ignore(state.render_root())
  })
  let render_issues = run_bench("RepoState::render_issues", iterations, fn() {
    ignore(state.render_issues())
  })

  println("---")
  print_result(repo_state_new)
  print_result(scan_files)
  print_result(load_issues)
  print_result(render_root)
  print_result(render_issues)
}
