///|
test "mars_route_specs contains home and healthz" {
  let routes = mars_route_specs()
  inspect(routes.length(), content="2")
  inspect(routes[0].http_method, content="GET")
  inspect(routes[0].path, content="/")
  inspect(routes[1].http_method, content="GET")
  inspect(routes[1].path, content="/healthz")
}

///|
test "texts are stable for adapter boundary" {
  inspect(home_text(), content="bithub: mars-first bootstrap")
  inspect(healthz_text(), content="ok")
}
