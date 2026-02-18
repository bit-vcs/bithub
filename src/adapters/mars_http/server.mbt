///|
pub fn create_app() -> @mars.Server {
  let app = @mars.Server::new()
  let api = @core.ApiState::new()
  let _ = app
    ..get("/", fn(ctx) { ctx.html(api.render_home_html()) })
    ..get("/healthz", fn(ctx) { ctx.text(@core.healthz_text()) })
    ..get("/readme", fn(ctx) { ctx.html(api.render_readme_html()) })
    ..get("/filer", fn(ctx) {
      let path = ctx.query("path").unwrap_or("")
      ctx.html(api.render_filer_html(path))
    })
    ..get("/file", fn(ctx) {
      let path = ctx.query("path").unwrap_or("")
      let res = api.render_file_response(path)
      ctx.html(res.body, status=res.status)
    })
  app
}
