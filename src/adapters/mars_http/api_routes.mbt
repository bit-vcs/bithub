///| Register all JSON API routes (POST /api/*).
/// These are pure data endpoints — no HTML rendering, no UI dependencies.
/// Any UI implementation can reuse these routes unchanged.
fn register_api_routes(app : @mars.Server, api : @core.ApiState) -> Unit {
  app.post(
    "/api/webhook/relay",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      let json_opt = ctx.body_json()
      match json_opt {
        Some(json) => {
          let runs = api.process_relay_webhook(json)
          // Auto-spawn CI containers if orchestrator is configured
          let spawn_config = get_spawn_config(ctx)
          match spawn_config {
            Some(config) =>
              for run in runs {
                let requests = api.build_spawn_requests(run.id)
                for req in requests {
                  @core.fire_spawn_request(config, req) |> ignore
                }
              }
            None => ()
          }
          // Log webhook
          let event_id = extract_json_string(json, "event_id")
          let event_type = extract_json_string(json, "event_type")
          let source = extract_json_string(json, "source")
          api.log_webhook(
            event_id,
            event_type,
            source,
            now_epoch_string(),
            runs.length(),
          )
          let resp : Map[String, Json] = {}
          resp.set("triggered", runs.length().to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let err : Map[String, Json] = {}
          err.set("error", "invalid json".to_json())
          ctx.json(err.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/actions/runs/status",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      let json_opt = ctx.body_json()
      match json_opt {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let run_id = match obj.get("run_id") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing run_id".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let job_id = match obj.get("job_id") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing job_id".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let step_index = match obj.get("step_index") {
            Some(Number(n, ..)) => n.to_int()
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing step_index".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let status = match obj.get("status") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing status".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let timestamp = timestamp_or_now(
            match obj.get("timestamp") {
              Some(String(s)) => s
              _ => ""
            },
          )
          let ok = api.update_step_status(
            run_id, job_id, step_index, status, timestamp,
          )
          let resp : Map[String, Json] = {}
          resp.set("ok", ok.to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/issues",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(token_info) else { return }
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let title = match obj.get("title") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing title".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let body = match obj.get("body") {
            Some(String(s)) => s
            _ => ""
          }
          let author = match obj.get("author") {
            Some(String(s)) => s
            _ => token_info.identity
          }
          let timestamp = timestamp_or_now(
            match obj.get("timestamp") {
              Some(String(s)) => s
              _ => ""
            },
          )
          let id = api.create_issue(title, body, author, timestamp)
          let resp : Map[String, Json] = {}
          resp.set("id", id.to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/issues/:id/comments",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(token_info) else { return }
      let issue_id = ctx.param("id").unwrap_or("")
      if issue_id.length() == 0 {
        let e : Map[String, Json] = {}
        e.set("error", "missing issue id".to_json())
        return ctx.json(e.to_json(), status=400)
      }
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let body = match obj.get("body") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing body".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let author = match obj.get("author") {
            Some(String(s)) => s
            _ => token_info.identity
          }
          let timestamp = timestamp_or_now(
            match obj.get("timestamp") {
              Some(String(s)) => s
              _ => ""
            },
          )
          let ok = api.add_comment(issue_id, author, body, timestamp)
          let resp : Map[String, Json] = {}
          resp.set("ok", ok.to_json())
          if !ok {
            resp.set("error", "issue not found".to_json())
          }
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/files",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(token_info) else { return }
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let path = match obj.get("path") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing path".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let content = match obj.get("content") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing content".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let message = match obj.get("message") {
            Some(String(s)) => s
            _ => "Edit " + path
          }
          let author = match obj.get("author") {
            Some(String(s)) => s
            _ => token_info.identity
          }
          let timestamp = timestamp_or_now(
            match obj.get("timestamp") {
              Some(String(s)) => s
              _ => ""
            },
          )
          let result = api.edit_file(path, content, message, author, timestamp)
          let resp : Map[String, Json] = {}
          resp.set("ok", result.ok.to_json())
          if result.ok {
            resp.set("commit_sha", result.commit_sha.to_json())
          } else {
            resp.set("error", result.error.to_json())
          }
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/files/sync",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          guard obj.get("files") is Some(Array(files_arr)) else {
            let e : Map[String, Json] = {}
            e.set("error", "missing files array".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let mut synced = 0
          for item in files_arr {
            guard item is Object(file_obj) else { continue }
            let path = match file_obj.get("path") {
              Some(String(s)) => s
              _ => continue
            }
            let content = match file_obj.get("content") {
              Some(String(s)) => s
              _ => continue
            }
            api.store.set_string(path, content)
            synced += 1
          }
          let resp : Map[String, Json] = {}
          resp.set("synced", synced.to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/pulls/:id/comments",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(token_info) else { return }
      let pr_id = ctx.param("id").unwrap_or("")
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let body = match obj.get("body") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing body".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let author = match obj.get("author") {
            Some(String(s)) => s
            _ => token_info.identity
          }
          let timestamp = timestamp_or_now(
            match obj.get("timestamp") {
              Some(String(s)) => s
              _ => ""
            },
          )
          let ok = api.add_pr_comment(pr_id, author, body, timestamp)
          let resp : Map[String, Json] = {}
          resp.set("ok", ok.to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/issues/:id/state",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      let issue_id = ctx.param("id").unwrap_or("")
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let state = match obj.get("state") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing state (open/closed)".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let ok = api.update_issue_state(issue_id, state)
          let resp : Map[String, Json] = {}
          resp.set("ok", ok.to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/pulls",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(token_info) else { return }
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let title = match obj.get("title") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing title".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let body = match obj.get("body") {
            Some(String(s)) => s
            _ => ""
          }
          let base_ref = match obj.get("base") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing base".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let head_ref = match obj.get("head") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing head".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let author = match obj.get("author") {
            Some(String(s)) => s
            _ => token_info.identity
          }
          let timestamp = timestamp_or_now(
            match obj.get("timestamp") {
              Some(String(s)) => s
              _ => ""
            },
          )
          let id = api.create_pull_request(
            title, body, author, base_ref, head_ref, timestamp,
          )
          let resp : Map[String, Json] = {}
          resp.set("id", id.to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/pulls/:id/merge",
    @mars.handler(fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      let pr_id = ctx.param("id").unwrap_or("")
      let ok = api.merge_pull_request(pr_id)
      let resp : Map[String, Json] = {}
      resp.set("ok", ok.to_json())
      ctx.json(resp.to_json())
    }),
  )
  app.post(
    "/api/pulls/:id/close",
    @mars.handler(fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      let pr_id = ctx.param("id").unwrap_or("")
      let ok = api.close_pull_request(pr_id)
      let resp : Map[String, Json] = {}
      resp.set("ok", ok.to_json())
      ctx.json(resp.to_json())
    }),
  )
  // ---- PR Reviews ----
  app.post(
    "/api/pulls/:id/reviews",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(token_info) else { return }
      let pr_id = ctx.param("id").unwrap_or("")
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let state = match obj.get("state") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing state (approved/changes_requested/commented)".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let body = match obj.get("body") {
            Some(String(s)) => s
            _ => ""
          }
          let author = match obj.get("author") {
            Some(String(s)) => s
            _ => token_info.identity
          }
          let timestamp = timestamp_or_now(
            match obj.get("timestamp") {
              Some(String(s)) => s
              _ => ""
            },
          )
          let id = api.submit_pr_review(pr_id, author, state, body, timestamp)
          if id.length() == 0 {
            let e : Map[String, Json] = {}
            e.set("error", "PR not found".to_json())
            return ctx.json(e.to_json(), status=404)
          }
          // Auto-generate notification
          let pr_title = match api.get_pull_request(pr_id) {
            Some(detail) => detail.pr.title
            None => "PR #" + pr_id
          }
          let review_label = match state {
            "approved" => "approved"
            "changes_requested" => "requested changes on"
            _ => "commented on"
          }
          api.add_notification(
            "review",
            author + " " + review_label + " PR #" + pr_id + " " + pr_title,
            "/pulls/" + pr_id,
            author,
            timestamp,
          ) |> ignore
          let resp : Map[String, Json] = {}
          resp.set("id", id.to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  // ---- Notifications ----
  app.post(
    "/api/notifications/read",
    @mars.handler(fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      let count = api.mark_all_notifications_read()
      let resp : Map[String, Json] = {}
      resp.set("marked", count.to_json())
      ctx.json(resp.to_json())
    }),
  )
  app.post(
    "/api/notifications/:id/read",
    @mars.handler(fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      let nid = ctx.param("id").unwrap_or("")
      let ok = api.mark_notification_read(nid)
      let resp : Map[String, Json] = {}
      resp.set("ok", ok.to_json())
      ctx.json(resp.to_json())
    }),
  )
  // ---- Releases ----
  app.post(
    "/api/releases",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(token_info) else { return }
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let tag_name = match obj.get("tag_name") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing tag_name".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let name = match obj.get("name") {
            Some(String(s)) => s
            _ => tag_name
          }
          let body = match obj.get("body") {
            Some(String(s)) => s
            _ => ""
          }
          let author = match obj.get("author") {
            Some(String(s)) => s
            _ => token_info.identity
          }
          let draft = match obj.get("draft") {
            Some(True) => true
            _ => false
          }
          let prerelease = match obj.get("prerelease") {
            Some(True) => true
            _ => false
          }
          let timestamp = timestamp_or_now(
            match obj.get("timestamp") {
              Some(String(s)) => s
              _ => ""
            },
          )
          let id = api.create_release(
            tag_name, name, body, author, timestamp, draft, prerelease,
          )
          let resp : Map[String, Json] = {}
          resp.set("id", id.to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/releases/:id/delete",
    @mars.handler(fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      let release_id = ctx.param("id").unwrap_or("")
      let ok = api.delete_release(release_id)
      let resp : Map[String, Json] = {}
      resp.set("ok", ok.to_json())
      ctx.json(resp.to_json())
    }),
  )
  // ---- Labels ----
  app.post(
    "/api/labels",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let name = match obj.get("name") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing name".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let color = match obj.get("color") {
            Some(String(s)) => s
            _ => "cccccc"
          }
          let description = match obj.get("description") {
            Some(String(s)) => s
            _ => ""
          }
          let ok = api.create_label(name, color, description)
          let resp : Map[String, Json] = {}
          resp.set("ok", ok.to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/issues/:id/labels",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      let issue_id = ctx.param("id").unwrap_or("")
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let label = match obj.get("label") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing label".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let ok = api.add_issue_label(issue_id, label)
          let resp : Map[String, Json] = {}
          resp.set("ok", ok.to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  // ---- Milestones ----
  app.post(
    "/api/milestones",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let title = match obj.get("title") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing title".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let description = match obj.get("description") {
            Some(String(s)) => s
            _ => ""
          }
          let due_date = match obj.get("due_date") {
            Some(String(s)) => s
            _ => ""
          }
          let timestamp = timestamp_or_now(
            match obj.get("timestamp") {
              Some(String(s)) => s
              _ => ""
            },
          )
          let id = api.create_milestone(title, description, due_date, timestamp)
          let resp : Map[String, Json] = {}
          resp.set("id", id.to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/milestones/:id/state",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      let ms_id = ctx.param("id").unwrap_or("")
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let state = match obj.get("state") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing state".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let ok = api.update_milestone_state(ms_id, state)
          let resp : Map[String, Json] = {}
          resp.set("ok", ok.to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/issues/:id/milestone",
    @mars.handler(async fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      let issue_id = ctx.param("id").unwrap_or("")
      match ctx.body_json() {
        Some(json) => {
          guard json is Object(obj) else {
            let e : Map[String, Json] = {}
            e.set("error", "invalid payload".to_json())
            return ctx.json(e.to_json(), status=400)
          }
          let milestone_id = match obj.get("milestone_id") {
            Some(String(s)) => s
            _ => {
              let e : Map[String, Json] = {}
              e.set("error", "missing milestone_id".to_json())
              return ctx.json(e.to_json(), status=400)
            }
          }
          let ok = api.assign_issue_milestone(issue_id, milestone_id)
          let resp : Map[String, Json] = {}
          resp.set("ok", ok.to_json())
          ctx.json(resp.to_json())
        }
        None => {
          let e : Map[String, Json] = {}
          e.set("error", "invalid json".to_json())
          ctx.json(e.to_json(), status=400)
        }
      }
    }),
  )
  app.post(
    "/api/trigger",
    @mars.handler(fn(ctx) {
      guard require_write(api, ctx) is Some(_) else { return }
      let runs = api.process_relay_webhook({
        "event_type": "relay.incoming_ref",
        "event_id": "local-" + @core.simple_hash(now_epoch_string()),
        "ref": "refs/relay/incoming/main",
        "source": "local-trigger",
        "occurred_at": 0,
        "room": "main",
        "target": "session:local",
      })
      let resp : Map[String, Json] = {}
      resp.set("triggered", runs.length().to_json())
      ctx.json(resp.to_json())
    }),
  )
}
