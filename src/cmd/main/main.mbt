///|
pub fn fetch(
  request : @mars.JsRequest,
  env : @mars.JsEnv,
  exec_ctx : @mars.JsExecCtx,
) -> @js_async.Promise[@mars.JsResponse] {
  let app = @mars_http.create_app()
  let handler = app.to_handler_with_env(env, exec_ctx)
  handler(request)
}
