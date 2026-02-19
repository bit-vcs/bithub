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
  ensure_sol_reschedule_symbol()
  @sol.run_app(fn() { @mars_http.create_app() }, port=port)
}
