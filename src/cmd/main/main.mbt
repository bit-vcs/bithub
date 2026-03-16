///|
let lazy_app : Ref[@mars.Server?] = Ref::new(None)

///|
fn get_app() -> @mars.Server {
  match lazy_app.val {
    Some(app) => app
    None => {
      let app = @mars_http.create_app()
      lazy_app.val = Some(app)
      app
    }
  }
}

///|
pub fn fetch(
  request : @mars.JsRequest,
  env : @mars.JsEnv,
  exec_ctx : @mars.JsExecCtx,
) -> @js_async.Promise[@mars.JsResponse] {
  let app = get_app()
  let handler = app.to_handler_with_env(env, exec_ctx)
  handler(request)
}

///|
fn main {
  // Workers entry: fetch is exported via ESM, main is unused
}
