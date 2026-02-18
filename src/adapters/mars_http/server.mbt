///|
pub fn create_app() -> @mars.Server {
  let app = @mars.Server::new()
  app
  ..get("/", fn(ctx) { ctx.text(@core.home_text()) })
  .get("/healthz", fn(ctx) { ctx.text(@core.healthz_text()) })
  app
}
