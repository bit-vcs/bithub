///|
pub struct CiRun {
  id : String
  workflow_file : String
  workflow_name : String
  ref_name : String
  status : String
  triggered_at : String
  source : String
}

///|
pub struct CiJobRun {
  job_id : String
  name : String
  status : String
  started_at : String
  finished_at : String
}

///|
pub struct CiStepRun {
  index : Int
  name : String
  status : String
  started_at : String
  finished_at : String
  uses : String
  run_cmd : String
}

///|
pub struct CiRunDetail {
  run : CiRun
  jobs : Array[CiJobRunDetail]
}

///|
pub struct CiJobRunDetail {
  job : CiJobRun
  steps : Array[CiStepRun]
}

///|
pub fn extract_branch_from_relay_ref(relay_ref : String) -> String? {
  let prefix = "refs/relay/incoming/"
  if relay_ref.has_prefix(prefix) {
    Some(
      String::unsafe_substring(
        relay_ref,
        start=prefix.length(),
        end=relay_ref.length(),
      ),
    )
  } else {
    None
  }
}

///|
pub fn ApiState::process_relay_webhook(
  self : ApiState,
  json : Json,
) -> Array[CiRun] {
  let runs : Array[CiRun] = []
  guard json is Object(obj) else { return runs }
  let event_type = match obj.get("event_type") {
    Some(String(s)) => s
    _ => return runs
  }
  if event_type != "relay.incoming_ref" {
    return runs
  }
  let event_id = match obj.get("event_id") {
    Some(String(s)) => s
    _ => return runs
  }
  let occurred_at = match obj.get("occurred_at") {
    Some(Number(n, ..)) => n.to_int().to_string()
    _ => ""
  }
  let source = match obj.get("source") {
    Some(String(s)) => s
    _ => ""
  }
  let ref_str = match obj.get("ref") {
    Some(String(s)) => s
    _ => return runs
  }
  let branch = match extract_branch_from_relay_ref(ref_str) {
    Some(b) => b
    None => return runs
  }
  let push_event = @actrun.new_push_event(branch, [])
  let workflow_dir = ".github/workflows"
  let names = self.store.list(workflow_dir)
  for name in names {
    if not(name.has_suffix(".yml") || name.has_suffix(".yaml")) {
      continue
    }
    let path = workflow_dir + "/" + name
    match self.store.get(path) {
      Some(bytes) => {
        let text = @utf8.decode_lossy(bytes)
        let result = @actrun.parse_workflow_yaml(text)
        match result.workflow {
          Some(spec) => {
            if @actrun.matches_push_trigger(spec.trigger, push_event) {
              let wf_name = if spec.name.length() > 0 {
                spec.name
              } else {
                name
              }
              let run : CiRun = {
                id: event_id,
                workflow_file: name,
                workflow_name: wf_name,
                ref_name: branch,
                status: "pending",
                triggered_at: occurred_at,
                source,
              }
              self.store.set_string(
                "ci/runs/" + event_id,
                serialize_ci_run(run),
              )
              // Create job and step entries
              for job in spec.jobs {
                let job_name = if job.name.length() > 0 {
                  job.name
                } else {
                  job.id
                }
                let job_run : CiJobRun = {
                  job_id: job.id,
                  name: job_name,
                  status: "pending",
                  started_at: "",
                  finished_at: "",
                }
                self.store.set_string(
                  "ci/jobs/" + event_id + "/" + job.id,
                  serialize_ci_job_run(job_run),
                )
                let mut step_idx = 0
                for step in job.steps {
                  let step_name = if step.name.length() > 0 {
                    step.name
                  } else {
                    step.id
                  }
                  let run_preview = match step.run {
                    Some(r) =>
                      if r.length() > 80 {
                        String::unsafe_substring(r, start=0, end=80)
                      } else {
                        r
                      }
                    None => ""
                  }
                  let step_run : CiStepRun = {
                    index: step_idx,
                    name: step_name,
                    status: "pending",
                    started_at: "",
                    finished_at: "",
                    uses: step.uses.unwrap_or(""),
                    run_cmd: run_preview,
                  }
                  self.store.set_string(
                    "ci/steps/" +
                    event_id +
                    "/" +
                    job.id +
                    "/" +
                    step_idx.to_string(),
                    serialize_ci_step_run(step_run),
                  )
                  step_idx += 1
                }
              }
              runs.push(run)
            }
          }
          None => ()
        }
      }
      None => ()
    }
  }
  runs
}

///|
pub fn ApiState::list_ci_runs(self : ApiState) -> Array[CiRun] {
  let runs : Array[CiRun] = []
  let ids = self.store.list("ci/runs")
  for id in ids {
    let key = "ci/runs/" + id
    match self.store.get(key) {
      Some(bytes) => {
        let text = @utf8.decode_lossy(bytes)
        match deserialize_ci_run(text) {
          Some(run) => runs.push(run)
          None => ()
        }
      }
      None => ()
    }
  }
  runs
}

///|
pub fn ApiState::get_ci_run(self : ApiState, id : String) -> CiRun? {
  let key = "ci/runs/" + id
  match self.store.get(key) {
    Some(bytes) => deserialize_ci_run(@utf8.decode_lossy(bytes))
    None => None
  }
}

///|
pub fn ApiState::get_ci_run_detail(
  self : ApiState,
  run_id : String,
) -> CiRunDetail? {
  let run = match self.get_ci_run(run_id) {
    Some(r) => r
    None => return None
  }
  let jobs : Array[CiJobRunDetail] = []
  let job_ids = self.store.list("ci/jobs/" + run_id)
  job_ids.sort_by(fn(a, b) { String::compare(a, b) })
  for job_id in job_ids {
    let job_key = "ci/jobs/" + run_id + "/" + job_id
    let job_run = match self.store.get(job_key) {
      Some(bytes) =>
        match deserialize_ci_job_run(@utf8.decode_lossy(bytes)) {
          Some(j) => j
          None => continue
        }
      None => continue
    }
    let steps : Array[CiStepRun] = []
    let step_ids = self.store.list("ci/steps/" + run_id + "/" + job_id)
    for step_id in step_ids {
      let step_key = "ci/steps/" + run_id + "/" + job_id + "/" + step_id
      match self.store.get(step_key) {
        Some(bytes) =>
          match deserialize_ci_step_run(@utf8.decode_lossy(bytes)) {
            Some(s) => steps.push(s)
            None => ()
          }
        None => ()
      }
    }
    steps.sort_by(fn(a, b) { a.index.compare(b.index) })
    jobs.push({ job: job_run, steps })
  }
  Some({ run, jobs })
}

///|
pub fn ApiState::update_step_status(
  self : ApiState,
  run_id : String,
  job_id : String,
  step_index : Int,
  status : String,
  timestamp : String,
) -> Bool {
  let step_key = "ci/steps/" +
    run_id +
    "/" +
    job_id +
    "/" +
    step_index.to_string()
  let step_run = match self.store.get(step_key) {
    Some(bytes) =>
      match deserialize_ci_step_run(@utf8.decode_lossy(bytes)) {
        Some(s) => s
        None => return false
      }
    None => return false
  }
  // Update step
  let started = if step_run.started_at.length() == 0 && status == "running" {
    timestamp
  } else {
    step_run.started_at
  }
  let finished = if status == "success" || status == "failure" || status == "skipped" {
    timestamp
  } else {
    step_run.finished_at
  }
  let updated_step : CiStepRun = {
    ..step_run,
    status,
    started_at: started,
    finished_at: finished,
  }
  self.store.set_string(step_key, serialize_ci_step_run(updated_step))
  // Recompute job status
  let step_ids = self.store.list("ci/steps/" + run_id + "/" + job_id)
  let step_statuses : Array[String] = []
  for sid in step_ids {
    let sk = "ci/steps/" + run_id + "/" + job_id + "/" + sid
    match self.store.get(sk) {
      Some(bytes) =>
        match deserialize_ci_step_run(@utf8.decode_lossy(bytes)) {
          Some(s) => step_statuses.push(s.status)
          None => ()
        }
      None => ()
    }
  }
  let job_status = derive_status(step_statuses)
  let job_key = "ci/jobs/" + run_id + "/" + job_id
  match self.store.get(job_key) {
    Some(bytes) =>
      match deserialize_ci_job_run(@utf8.decode_lossy(bytes)) {
        Some(j) => {
          let j_started = if j.started_at.length() == 0 &&
            job_status == "running" {
            timestamp
          } else {
            j.started_at
          }
          let j_finished = if job_status == "success" || job_status == "failure" {
            timestamp
          } else {
            j.finished_at
          }
          self.store.set_string(
            job_key,
            serialize_ci_job_run(
              { ..j, status: job_status, started_at: j_started, finished_at: j_finished },
            ),
          )
        }
        None => ()
      }
    None => ()
  }
  // Recompute run status
  let all_job_ids = self.store.list("ci/jobs/" + run_id)
  let job_statuses : Array[String] = []
  for jid in all_job_ids {
    let jk = "ci/jobs/" + run_id + "/" + jid
    match self.store.get(jk) {
      Some(bytes) =>
        match deserialize_ci_job_run(@utf8.decode_lossy(bytes)) {
          Some(j) => job_statuses.push(j.status)
          None => ()
        }
      None => ()
    }
  }
  let run_status = derive_status(job_statuses)
  match self.get_ci_run(run_id) {
    Some(r) =>
      self.store.set_string(
        "ci/runs/" + run_id,
        serialize_ci_run({ ..r, status: run_status }),
      )
    None => ()
  }
  true
}

///|
fn derive_status(statuses : Array[String]) -> String {
  let mut any_running = false
  let mut any_failure = false
  let mut all_done = true
  for s in statuses {
    if s == "running" {
      any_running = true
    }
    if s == "failure" {
      any_failure = true
    }
    if s != "success" && s != "failure" && s != "skipped" {
      all_done = false
    }
  }
  if any_running {
    return "running"
  }
  if all_done && statuses.length() > 0 {
    if any_failure {
      return "failure"
    }
    return "success"
  }
  if any_failure {
    return "failure"
  }
  "pending"
}

// ---- Serialization ----

///|
fn serialize_ci_run(run : CiRun) -> String {
  [
    "id=" + run.id,
    "workflow_file=" + run.workflow_file,
    "workflow_name=" + run.workflow_name,
    "ref_name=" + run.ref_name,
    "status=" + run.status,
    "triggered_at=" + run.triggered_at,
    "source=" + run.source,
  ].join("\n")
}

///|
fn serialize_ci_job_run(job : CiJobRun) -> String {
  [
    "job_id=" + job.job_id,
    "name=" + job.name,
    "status=" + job.status,
    "started_at=" + job.started_at,
    "finished_at=" + job.finished_at,
  ].join("\n")
}

///|
fn serialize_ci_step_run(step : CiStepRun) -> String {
  [
    "index=" + step.index.to_string(),
    "name=" + step.name,
    "status=" + step.status,
    "started_at=" + step.started_at,
    "finished_at=" + step.finished_at,
    "uses=" + step.uses,
    "run_cmd=" + step.run_cmd,
  ].join("\n")
}


///|
fn deserialize_ci_run(text : String) -> CiRun? {
  let f = parse_kv_fields(text)
  let id = f.get("id").unwrap_or("")
  if id.length() == 0 {
    return None
  }
  Some({
    id,
    workflow_file: f.get("workflow_file").unwrap_or(""),
    workflow_name: f.get("workflow_name").unwrap_or(""),
    ref_name: f.get("ref_name").unwrap_or(""),
    status: f.get("status").unwrap_or(""),
    triggered_at: f.get("triggered_at").unwrap_or(""),
    source: f.get("source").unwrap_or(""),
  })
}

///|
fn deserialize_ci_job_run(text : String) -> CiJobRun? {
  let f = parse_kv_fields(text)
  let job_id = f.get("job_id").unwrap_or("")
  if job_id.length() == 0 {
    return None
  }
  Some({
    job_id,
    name: f.get("name").unwrap_or(""),
    status: f.get("status").unwrap_or(""),
    started_at: f.get("started_at").unwrap_or(""),
    finished_at: f.get("finished_at").unwrap_or(""),
  })
}

///|
fn deserialize_ci_step_run(text : String) -> CiStepRun? {
  let f = parse_kv_fields(text)
  let idx_str = f.get("index").unwrap_or("")
  if idx_str.length() == 0 {
    return None
  }
  let idx = try {
    @strconv.parse_int!(idx_str)
  } catch {
    _ => return None
  }
  Some({
    index: idx,
    name: f.get("name").unwrap_or(""),
    status: f.get("status").unwrap_or(""),
    started_at: f.get("started_at").unwrap_or(""),
    finished_at: f.get("finished_at").unwrap_or(""),
    uses: f.get("uses").unwrap_or(""),
    run_cmd: f.get("run_cmd").unwrap_or(""),
  })
}
