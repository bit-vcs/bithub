///|
pub fn create_app() -> @mars.Server {
  let app = @mars.Server::new()
  app
  ..get("/", async fn(ctx) { ctx.text(@core.home_text()) })
  .get("/healthz", async fn(ctx) { ctx.text(@core.healthz_text()) })
  app
}
