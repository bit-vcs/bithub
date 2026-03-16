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
    {
      id: "actions",
      http_method: "GET",
      path: "/actions",
    },
    {
      id: "actions_workflows",
      http_method: "GET",
      path: "/actions/workflows",
    },
    {
      id: "actions_workflow",
      http_method: "GET",
      path: "/actions/workflows/:file",
    },
    {
      id: "actions_run",
      http_method: "GET",
      path: "/actions/runs/:id",
    },
    {
      id: "webhook_relay",
      http_method: "POST",
      path: "/api/webhook/relay",
    },
    {
      id: "actions_run_status",
      http_method: "POST",
      path: "/api/actions/runs/status",
    },
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
