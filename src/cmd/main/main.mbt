///|
async fn main {
  let app = @mars_http.create_app()
  app.serve(host="127.0.0.1", port=3000)
}
