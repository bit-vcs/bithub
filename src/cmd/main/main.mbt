///|
let lazy_app : Ref[@mars.Server?] = Ref::new(None)
let r2_initialized : Ref[Bool] = Ref::new(false)

///|
fn get_app(env : @mars.JsEnv) -> @mars.Server {
  match lazy_app.val {
    Some(app) => app
    None => {
      let app = if has_r2_binding(env) && !r2_initialized.val {
        // Use R2-backed storage on Cloudflare Workers
        r2_initialized.val = true
        let r2 = @core.R2Storage::new("BITHUB_STORE")
        let api = @core.ApiState::with_storage(r2)
        // Seed default auth token if not present
        if api.resolve_token("tok-owner-001") is None {
          r2.set_string("auth/tokens/tok-owner-001", "identity=admin\nrole=owner")
          r2.set_string("auth/tokens/tok-write-001", "identity=ci-bot\nrole=write")
          r2.set_string("auth/tokens/tok-alice", "identity=agent-alice\nrole=owner")
          r2.set_string("auth/tokens/tok-bob", "identity=agent-bob\nrole=write")
        }
        @mars_http.create_app_with_storage(api)
      } else {
        // Fallback to in-memory seeded storage
        @mars_http.create_app()
      }
      lazy_app.val = Some(app)
      app
    }
  }
}

///|
extern "js" fn has_r2_binding(env : @mars.JsEnv) -> Bool =
  #| (env) => {
  #|   return env && typeof env.BITHUB_STORE === 'object' && env.BITHUB_STORE !== null;
  #| }

///|
pub fn fetch(
  request : @mars.JsRequest,
  env : @mars.JsEnv,
  exec_ctx : @mars.JsExecCtx,
) -> @js_async.Promise[@mars.JsResponse] {
  let app = get_app(env)
  let handler = app.to_handler_with_env(env, exec_ctx)
  handler(request)
}

///|
fn main {
  // Workers entry: fetch is exported via ESM, main is unused
}
