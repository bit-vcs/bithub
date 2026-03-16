///|
fn parse_port(raw : String) -> Int {
  let parsed = @strconv.parse_int(raw) catch { _ => 4174 }
  if parsed > 0 {
    parsed
  } else {
    4174
  }
}

///|
pub extern "js" fn ensure_sol_reschedule_symbol() -> Unit =
  #| () => {
  #|   const key = "moonbitlang$async$internal$event_loop$$reschedule";
  #|   if (typeof globalThis[key] !== "function") {
  #|     globalThis[key] = () => {};
  #|   }
  #| }

///|
fn main {
  let argv = @nprocess.argv()
  let port = if argv.length() > 2 { parse_port(argv[2]) } else { 4174 }
  let repo = if argv.length() > 3 { Some(argv[3]) } else { None }
  ensure_sol_reschedule_symbol()
  @sol.run_app(
    fn() {
      match repo {
        Some(root) => {
          println("mars_http: loading repo from " + root)
          @mars_http.create_app_from_repo(root)
        }
        None => @mars_http.create_app()
      }
    },
    port=port,
  )
}
