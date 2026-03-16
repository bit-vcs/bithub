///| CI Container Spawn: triggers external CI runner when webhook creates runs.
///  Uses JS fetch to POST spawn requests to a configurable orchestrator URL.

///|
pub(all) struct CiSpawnConfig {
  orchestrator_url : String
  auth_token : String
  bithub_url : String
  bithub_token : String
  container_image : String
}

///|
pub struct CiSpawnRequest {
  run_id : String
  job_id : String
  job_name : String
  steps : Array[CiSpawnStep]
  repo_url : String
  ref_name : String
}

///|
pub struct CiSpawnStep {
  index : Int
  name : String
  uses : String
  run_cmd : String
}

///|
pub fn ApiState::build_spawn_requests(
  self : ApiState,
  run_id : String,
) -> Array[CiSpawnRequest] {
  let requests : Array[CiSpawnRequest] = []
  match self.get_ci_run_detail(run_id) {
    Some(detail) => {
      for job_detail in detail.jobs {
        let steps : Array[CiSpawnStep] = []
        for step in job_detail.steps {
          steps.push({
            index: step.index,
            name: step.name,
            uses: step.uses,
            run_cmd: step.run_cmd,
          })
        }
        requests.push({
          run_id,
          job_id: job_detail.job.job_id,
          job_name: job_detail.job.name,
          steps,
          repo_url: "",
          ref_name: detail.run.ref_name,
        })
      }
    }
    None => ()
  }
  requests
}

///|
pub fn spawn_request_to_env_json(
  req : CiSpawnRequest,
  config : CiSpawnConfig,
) -> String {
  let sb = StringBuilder::new()
  sb.write_string("{")
  sb.write_string("\"BITHUB_URL\":\"" + config.bithub_url + "\",")
  sb.write_string("\"BITHUB_TOKEN\":\"" + config.bithub_token + "\",")
  sb.write_string("\"CI_RUN_ID\":\"" + req.run_id + "\",")
  sb.write_string("\"CI_JOB_ID\":\"" + req.job_id + "\",")
  sb.write_string("\"CI_REF\":\"" + req.ref_name + "\"")
  if req.repo_url.length() > 0 {
    sb.write_string(",\"CI_REPO_URL\":\"" + req.repo_url + "\"")
  }
  // Encode steps as CI_STEP_0, CI_STEP_1, ...
  for step in req.steps {
    let cmd = if step.run_cmd.length() > 0 {
      step.run_cmd
    } else if step.uses.length() > 0 {
      "echo 'uses: " + step.uses + "'"
    } else {
      "echo 'no-op'"
    }
    sb.write_string(
      ",\"CI_STEP_" +
      step.index.to_string() +
      "\":\"" +
      simple_base64_encode(cmd) +
      "\"",
    )
  }
  sb.write_string("}")
  sb.to_string()
}

///|
fn simple_base64_encode(input : String) -> String {
  base64_encode_js(input)
}

///|
extern "js" fn base64_encode_js(input : String) -> String =
  #| (input) => {
  #|   if (typeof btoa === 'function') return btoa(input);
  #|   return Buffer.from(input).toString('base64');
  #| }

///|
/// Fire-and-forget: POST spawn request to orchestrator.
/// Returns true if the request was sent (not necessarily completed).
pub fn fire_spawn_request(
  config : CiSpawnConfig,
  req : CiSpawnRequest,
) -> Bool {
  let env_json = spawn_request_to_env_json(req, config)
  let payload = "{\"image\":\"" +
    config.container_image +
    "\",\"env\":" +
    env_json +
    "}"
  fire_and_forget_post(
    config.orchestrator_url + "/api/spawn",
    config.auth_token,
    payload,
  )
  true
}

///|
extern "js" fn fire_and_forget_post(
  url : String,
  auth_token : String,
  body : String,
) -> Unit =
  #| (url, auth_token, body) => {
  #|   try {
  #|     const headers = { 'Content-Type': 'application/json' };
  #|     if (auth_token) headers['Authorization'] = 'Bearer ' + auth_token;
  #|     fetch(url, { method: 'POST', headers, body }).catch(() => {});
  #|   } catch {}
  #| }
