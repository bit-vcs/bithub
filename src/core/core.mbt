///|
pub struct RouteSpec {
  id : String
  http_method : String
  path : String
}

///|
pub fn mars_route_specs() -> Array[RouteSpec] {
  [
    { id: "home", http_method: "GET", path: "/" },
    { id: "healthz", http_method: "GET", path: "/healthz" },
    { id: "readme", http_method: "GET", path: "/readme" },
    { id: "filer", http_method: "GET", path: "/filer" },
    { id: "file", http_method: "GET", path: "/file" },
  ]
}

///|
pub fn home_text() -> String {
  "bithub: mars-first bootstrap"
}

///|
pub fn healthz_text() -> String {
  "ok"
}
