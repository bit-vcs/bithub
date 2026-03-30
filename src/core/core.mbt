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
      id: "commits",
      http_method: "GET",
      path: "/commits",
    },
    {
      id: "commit_detail",
      http_method: "GET",
      path: "/commit/:sha",
    },
    {
      id: "branches",
      http_method: "GET",
      path: "/branches",
    },
    {
      id: "blame",
      http_method: "GET",
      path: "/blame",
    },
    {
      id: "issues_create",
      http_method: "POST",
      path: "/api/issues",
    },
    {
      id: "issues_comment",
      http_method: "POST",
      path: "/api/issues/:id/comments",
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
    {
      id: "activity_graph",
      http_method: "GET",
      path: "/graph",
    },
    {
      id: "releases",
      http_method: "GET",
      path: "/releases",
    },
    {
      id: "release_detail",
      http_method: "GET",
      path: "/releases/:id",
    },
    {
      id: "releases_create",
      http_method: "POST",
      path: "/api/releases",
    },
    {
      id: "labels",
      http_method: "GET",
      path: "/labels",
    },
    {
      id: "labels_create",
      http_method: "POST",
      path: "/api/labels",
    },
    {
      id: "milestones",
      http_method: "GET",
      path: "/milestones",
    },
    {
      id: "milestone_detail",
      http_method: "GET",
      path: "/milestones/:id",
    },
    {
      id: "milestones_create",
      http_method: "POST",
      path: "/api/milestones",
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
