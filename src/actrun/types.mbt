// Vendored subset of mizchi/actrun types for workflow parsing.

///|
pub struct RunDefaults {
  shell : String?
  working_directory : String?
}

///|
pub struct PermissionsSpec {
  values : Map[String, String]
}

///|
pub struct ConcurrencySpec {
  group : String
  cancel_in_progress : String?
}

///|
pub struct WorkflowCallInputSpec {
  description : String
  required : Bool
  default_value : String?
  input_type : String
}

///|
pub struct WorkflowCallOutputSpec {
  description : String
  value : String
}

///|
pub struct WorkflowCallSecretSpec {
  required : Bool
}

///|
pub struct JobContainerCredentialsSpec {
  username : String
  password : String
}

///|
pub struct JobContainerSpec {
  image : String
  credentials : JobContainerCredentialsSpec?
  env : Map[String, String]
  ports : Array[String]
  volumes : Array[String]
  options : String?
}

///|
pub struct WorkflowCallSpec {
  inputs : Map[String, WorkflowCallInputSpec]
  outputs : Map[String, WorkflowCallOutputSpec]
  secrets : Map[String, WorkflowCallSecretSpec]
}

///|
pub fn new_permissions_spec(
  values? : Map[String, String] = {},
) -> PermissionsSpec {
  { values, }
}

///|
pub fn new_concurrency_spec(
  group : String,
  cancel_in_progress? : String? = None,
) -> ConcurrencySpec {
  { group, cancel_in_progress }
}

///|
pub fn new_workflow_call_input_spec(
  description? : String = "",
  required? : Bool = false,
  default_value? : String? = None,
  input_type? : String = "",
) -> WorkflowCallInputSpec {
  { description, required, default_value, input_type }
}

///|
pub fn new_workflow_call_output_spec(
  description? : String = "",
  value? : String = "",
) -> WorkflowCallOutputSpec {
  { description, value }
}

///|
pub fn new_workflow_call_secret_spec(
  required? : Bool = false,
) -> WorkflowCallSecretSpec {
  { required, }
}

///|
pub fn new_job_container_credentials_spec(
  username : String,
  password : String,
) -> JobContainerCredentialsSpec {
  { username, password }
}

///|
pub fn new_job_container_spec(
  image : String,
  credentials? : JobContainerCredentialsSpec? = None,
  env? : Map[String, String] = {},
  ports? : Array[String] = [],
  volumes? : Array[String] = [],
  options? : String? = None,
) -> JobContainerSpec {
  { image, credentials, env, ports, volumes, options }
}

///|
pub fn new_workflow_call_spec(
  inputs? : Map[String, WorkflowCallInputSpec] = {},
  outputs? : Map[String, WorkflowCallOutputSpec] = {},
  secrets? : Map[String, WorkflowCallSecretSpec] = {},
) -> WorkflowCallSpec {
  { inputs, outputs, secrets }
}

///|
pub fn new_run_defaults(
  shell? : String? = None,
  working_directory? : String? = None,
) -> RunDefaults {
  { shell, working_directory }
}

///|
pub struct PushTrigger {
  branches : Array[String]
  branches_ignore : Array[String]
  paths : Array[String]
  paths_ignore : Array[String]
  tags : Array[String]
  tags_ignore : Array[String]
}

///|
pub fn new_push_trigger(
  branches? : Array[String] = [],
  branches_ignore? : Array[String] = [],
  paths? : Array[String] = [],
  paths_ignore? : Array[String] = [],
  tags? : Array[String] = [],
  tags_ignore? : Array[String] = [],
) -> PushTrigger {
  { branches, branches_ignore, paths, paths_ignore, tags, tags_ignore }
}

///|
pub struct PushEvent {
  ref_name : String
  before_sha : String
  after_sha : String
  changed_paths : Array[String]
  repository : String
  actor : String
}

///|
pub fn new_push_event(
  ref_name : String,
  changed_paths : Array[String],
  before_sha? : String = "",
  after_sha? : String = "",
  repository? : String = "",
  actor? : String = "",
) -> PushEvent {
  { ref_name, before_sha, after_sha, changed_paths, repository, actor }
}

///|
pub struct StepSpec {
  id : String
  name : String
  run : String?
  uses : String?
  shell : String?
  working_directory : String?
  env : Map[String, String]
  with_values : Map[String, String]
  if_condition : String
  continue_on_error : String
  timeout_minutes : Int
}

///|
pub fn new_run_step(
  id : String,
  run : String,
  name? : String = "",
  shell? : String? = None,
  working_directory? : String? = None,
  env? : Map[String, String] = {},
  if_condition? : String = "success()",
  with_values? : Map[String, String] = {},
  continue_on_error? : String = "false",
  timeout_minutes? : Int = 0,
) -> StepSpec {
  {
    id,
    name,
    run: Some(run),
    uses: None,
    shell,
    working_directory,
    env,
    with_values,
    if_condition,
    continue_on_error,
    timeout_minutes,
  }
}

///|
pub fn new_uses_step(
  id : String,
  uses : String,
  name? : String = "",
  env? : Map[String, String] = {},
  if_condition? : String = "success()",
  with_values? : Map[String, String] = {},
  continue_on_error? : String = "false",
  timeout_minutes? : Int = 0,
) -> StepSpec {
  {
    id,
    name,
    run: None,
    uses: Some(uses),
    shell: None,
    working_directory: None,
    env,
    with_values,
    if_condition,
    continue_on_error,
    timeout_minutes,
  }
}

///|
pub struct JobSpec {
  id : String
  name : String
  if_condition : String
  needs : Array[String]
  outputs : Map[String, String]
  permissions : PermissionsSpec?
  concurrency : ConcurrencySpec?
  runs_on : Array[String]
  env : Map[String, String]
  defaults : RunDefaults
  steps : Array[StepSpec]
  matrix : JobMatrixSpec?
  reusable_workflow : String?
  reusable_workflow_with : Map[String, String]
  reusable_workflow_secrets : Map[String, String]
  reusable_workflow_inherit_secrets : Bool
  services : Map[String, JobContainerSpec]
  container : JobContainerSpec?
  container_image : String?
  timeout_minutes : Int
  environment : String
}

///|
pub struct JobMatrixSpec {
  rows : Array[Map[String, String]]
  fail_fast : Bool
  max_parallel : Int?
}

///|
pub fn new_job_matrix(
  rows : Array[Map[String, String]],
  fail_fast? : Bool = true,
  max_parallel? : Int? = None,
) -> JobMatrixSpec {
  { rows, fail_fast, max_parallel }
}

///|
pub fn new_job(
  id : String,
  steps : Array[StepSpec],
  name? : String = "",
  if_condition? : String = "success()",
  needs? : Array[String] = [],
  outputs? : Map[String, String] = {},
  permissions? : PermissionsSpec? = None,
  concurrency? : ConcurrencySpec? = None,
  runs_on? : Array[String] = ["ubuntu-latest"],
  env? : Map[String, String] = {},
  defaults? : RunDefaults = new_run_defaults(),
  matrix? : JobMatrixSpec? = None,
  reusable_workflow? : String? = None,
  reusable_workflow_with? : Map[String, String] = {},
  reusable_workflow_secrets? : Map[String, String] = {},
  reusable_workflow_inherit_secrets? : Bool = false,
  container? : JobContainerSpec? = None,
  container_image? : String? = None,
  services? : Map[String, JobContainerSpec] = {},
  timeout_minutes? : Int = 0,
  environment? : String = "",
) -> JobSpec {
  let actual_container = match container {
    Some(spec) => Some(spec)
    None =>
      match container_image {
        Some(image) => Some(new_job_container_spec(image))
        None => None
      }
  }
  let actual_container_image = match actual_container {
    Some(spec) => Some(spec.image)
    None => None
  }
  {
    id,
    name,
    if_condition,
    needs,
    outputs,
    permissions,
    concurrency,
    runs_on,
    env,
    defaults,
    steps,
    matrix,
    reusable_workflow,
    reusable_workflow_with,
    reusable_workflow_secrets,
    reusable_workflow_inherit_secrets,
    services,
    container: actual_container,
    container_image: actual_container_image,
    timeout_minutes,
    environment,
  }
}

///|
pub struct WorkflowSpec {
  name : String
  run_name : String
  trigger : PushTrigger
  workflow_call : Bool
  workflow_call_spec : WorkflowCallSpec?
  permissions : PermissionsSpec?
  concurrency : ConcurrencySpec?
  env : Map[String, String]
  defaults : RunDefaults
  jobs : Array[JobSpec]
}

///|
pub fn new_workflow(
  name : String,
  jobs : Array[JobSpec],
  run_name? : String = "",
  trigger? : PushTrigger = new_push_trigger(),
  workflow_call? : Bool = false,
  workflow_call_spec? : WorkflowCallSpec? = None,
  permissions? : PermissionsSpec? = None,
  concurrency? : ConcurrencySpec? = None,
  env? : Map[String, String] = {},
  defaults? : RunDefaults = new_run_defaults(),
) -> WorkflowSpec {
  {
    name,
    run_name,
    trigger,
    workflow_call,
    workflow_call_spec,
    permissions,
    concurrency,
    env,
    defaults,
    jobs,
  }
}

///|
pub struct WorkflowParseResult {
  workflow : WorkflowSpec?
  errors : Array[String]
}

///|
pub struct LocalActionSpec {
  name : String
  inputs : Map[String, String]
  steps : Array[StepSpec]
}

///|
pub fn new_local_action(
  steps : Array[StepSpec],
  name? : String = "",
  inputs? : Map[String, String] = {},
) -> LocalActionSpec {
  { name, inputs, steps }
}

///|
pub struct LocalActionParseResult {
  action : LocalActionSpec?
  errors : Array[String]
}
