///|
fn parse_port(raw : String) -> Int {
  let parsed = @string.parse_int(raw) catch { _ => 8787 }
  if parsed > 0 {
    parsed
  } else {
    8787
  }
}

///|
pub struct CliOptions {
  repo : String
  port : Int
  enable_p2p : Bool
  p2p_command_template : String?
  catalog_path : String?
  relay_url : String?
  relay_sender : String?
}

///|
fn parse_p2p_cmd_flag(arg : String) -> String? {
  let prefix = "--p2p-cmd="
  if arg.has_prefix(prefix) {
    Some(String::unsafe_substring(arg, start=prefix.length(), end=arg.length()))
  } else {
    None
  }
}

///|
fn parse_catalog_flag(arg : String) -> String? {
  let prefix = "--catalog="
  if arg.has_prefix(prefix) {
    Some(String::unsafe_substring(arg, start=prefix.length(), end=arg.length()))
  } else {
    None
  }
}

///|
fn parse_relay_flag(arg : String) -> String? {
  let prefix = "--relay="
  if arg.has_prefix(prefix) {
    Some(String::unsafe_substring(arg, start=prefix.length(), end=arg.length()))
  } else {
    None
  }
}

///|
fn parse_relay_sender_flag(arg : String) -> String? {
  let prefix = "--relay-sender="
  if arg.has_prefix(prefix) {
    Some(String::unsafe_substring(arg, start=prefix.length(), end=arg.length()))
  } else {
    None
  }
}

///|
pub fn parse_cli_options(argv : Array[String]) -> CliOptions {
  let positional : Array[String] = []
  let mut enable_p2p = false
  let mut p2p_command_template : String? = None
  let mut catalog_path : String? = None
  let mut relay_url : String? = None
  let mut relay_sender : String? = None

  let mut idx = 2
  while idx < argv.length() {
    let arg = argv[idx]
    if arg == "--p2p" || arg == "--public" {
      enable_p2p = true
    } else if arg == "--p2p-cmd" {
      enable_p2p = true
      if idx + 1 < argv.length() {
        p2p_command_template = Some(argv[idx + 1])
        idx += 1
      }
    } else if parse_p2p_cmd_flag(arg) is Some(cmd) {
      enable_p2p = true
      p2p_command_template = Some(cmd)
    } else if arg == "--catalog" {
      if idx + 1 < argv.length() {
        catalog_path = Some(argv[idx + 1])
        idx += 1
      }
    } else if parse_catalog_flag(arg) is Some(path) {
      catalog_path = Some(path)
    } else if arg == "--relay" {
      if idx + 1 < argv.length() {
        relay_url = Some(argv[idx + 1])
        idx += 1
      }
    } else if parse_relay_flag(arg) is Some(url) {
      relay_url = Some(url)
    } else if arg == "--relay-sender" {
      if idx + 1 < argv.length() {
        relay_sender = Some(argv[idx + 1])
        idx += 1
      }
    } else if parse_relay_sender_flag(arg) is Some(sender) {
      relay_sender = Some(sender)
    } else if arg.has_prefix("--") {
      ()
    } else {
      positional.push(arg)
    }
    idx += 1
  }

  let has_catalog = catalog_path is Some(_)
  let repo = if has_catalog {
    "."
  } else if positional.length() > 0 {
    positional[0]
  } else {
    "."
  }
  let port_raw = if has_catalog {
    if positional.length() > 0 {
      positional[0]
    } else {
      "8787"
    }
  } else if positional.length() > 1 {
    positional[1]
  } else {
    "8787"
  }
  {
    repo,
    port: parse_port(port_raw),
    enable_p2p,
    p2p_command_template,
    catalog_path,
    relay_url,
    relay_sender,
  }
}

///|
fn parse_args() -> CliOptions {
  parse_cli_options(@nprocess.argv())
}

///|
pub fn render_p2p_command(
  template : String,
  local_url : String,
  port : Int,
) -> String {
  template
  .replace(old="{url}", new=local_url)
  .replace(old="{port}", new=port.to_string())
}

///|
fn min_opt_int(a : Int?, b : Int?) -> Int? {
  match (a, b) {
    (Some(x), Some(y)) => Some(if x < y { x } else { y })
    (Some(x), None) => Some(x)
    (None, Some(y)) => Some(y)
    (None, None) => None
  }
}

///|
fn is_url_terminator(c : Char) -> Bool {
  c == ' ' ||
  c == '\t' ||
  c == '\r' ||
  c == '\n' ||
  c == '"' ||
  c == '\'' ||
  c == '<' ||
  c == '>' ||
  c == ')' ||
  c == ']' ||
  c == '}'
}

///|
pub fn extract_first_http_url(text : String) -> String? {
  let start = min_opt_int(text.find("https://"), text.find("http://"))
  match start {
    None => None
    Some(s) => {
      let tail = String::unsafe_substring(text, start=s, end=text.length())
      let end_rel = tail.find_by(is_url_terminator).unwrap_or(tail.length())
      if end_rel <= 0 {
        None
      } else {
        Some(String::unsafe_substring(tail, start=0, end=end_rel))
      }
    }
  }
}

///|
fn trim_trailing_slashes(path : String) -> String {
  let mut out = path
  while out.length() > 1 && out.has_suffix("/") {
    out = String::unsafe_substring(out, start=0, end=out.length() - 1)
  }
  out
}

///|
fn derive_catalog_name(path : String) -> String {
  let normalized = trim_trailing_slashes(path.trim(chars=" \n\r\t").to_string())
  if normalized == "." {
    return "."
  }
  match normalized.rev_find("/") {
    Some(i) if i + 1 < normalized.length() =>
      String::unsafe_substring(normalized, start=i + 1, end=normalized.length())
    _ => normalized
  }
}

///|
fn parse_catalog_line(line : String) -> (String, String)? {
  let normalized = line.trim(chars=" \n\r\t").to_string()
  if normalized.length() == 0 || normalized.has_prefix("#") {
    return None
  }
  match normalized.find("\t") {
    Some(i) => {
      let raw_name = String::unsafe_substring(normalized, start=0, end=i)
      let raw_path = String::unsafe_substring(
        normalized,
        start=i + 1,
        end=normalized.length(),
      )
      let path = raw_path.trim(chars=" \n\r\t").to_string()
      if path.length() == 0 {
        return None
      }
      let name = raw_name.trim(chars=" \n\r\t").to_string()
      if name.length() == 0 {
        Some((derive_catalog_name(path), path))
      } else {
        Some((name, path))
      }
    }
    None => {
      let path = normalized
      Some((derive_catalog_name(path), path))
    }
  }
}

///|
pub fn parse_catalog_text(text : String) -> Array[(String, String)] {
  let entries : Array[(String, String)] = []
  for line_view in text.split("\n") {
    let line = line_view.to_string()
    match parse_catalog_line(line) {
      Some(entry) => entries.push(entry)
      None => ()
    }
  }
  entries
}

///|
fn resolve_catalog_repo_path(
  catalog_path : String,
  repo_path : String,
) -> String {
  if @npath.isAbsolute(repo_path) {
    @npath.normalize(repo_path)
  } else {
    let base_dir = @npath.dirname(catalog_path)
    @npath.resolve([base_dir, repo_path])
  }
}

///|
priv struct CatalogRepo {
  id : String
  name : String
  root : String
  state : RepoState
}

///|
fn load_catalog_repos(catalog_path : String) -> Array[CatalogRepo] {
  let text = @nfs.read_file_as_string(catalog_path, encoding="utf-8") catch {
    _ => return []
  }
  let parsed = parse_catalog_text(text)
  let repos : Array[CatalogRepo] = []
  for i in 0..<parsed.length() {
    let id = "repo-" + (i + 1).to_string()
    let name = parsed[i].0
    let resolved_root = resolve_catalog_repo_path(catalog_path, parsed[i].1)
    let state = RepoState::new(resolved_root, route_base="/repo/" + id)
    repos.push({ id, name, root: resolved_root, state })
  }
  repos
}

///|
priv struct RelayOptions {
  base_url : String
  room : String
  sender : String
  auth_token : String?
}

///|
pub struct RelayPeer {
  sender : String
  url : String
  name : String
}

///|
fn parse_relay_base_url(raw : String) -> String? {
  let trimmed = trim_trailing_slashes(raw.trim(chars=" \n\r\t").to_string())
  if trimmed.length() == 0 {
    return None
  }
  if trimmed.has_prefix("relay+http://") || trimmed.has_prefix("relay+https://") {
    return Some(
      trim_trailing_slashes(
        String::unsafe_substring(trimmed, start=6, end=trimmed.length()),
      ),
    )
  }
  if trimmed.has_prefix("relay://") {
    let suffix = String::unsafe_substring(trimmed, start=8, end=trimmed.length())
    return Some(trim_trailing_slashes("http://" + suffix))
  }
  if trimmed.has_prefix("http://") || trimmed.has_prefix("https://") {
    return Some(trimmed)
  }
  None
}

///|
fn is_http_url(raw : String) -> Bool {
  raw.has_prefix("http://") || raw.has_prefix("https://")
}

///|
fn is_sender_safe_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '.' ||
  c == '_' ||
  c == '-'
}

///|
fn normalize_relay_sender(raw : String) -> String {
  let trimmed = raw.trim(chars=" \n\r\t").to_string()
  let out = StringBuilder::new()
  for c in trimmed {
    if is_sender_safe_char(c) {
      out.write_char(c)
    } else {
      out.write_char('-')
    }
  }
  let normalized = out.to_string()
  if normalized.length() == 0 {
    "bithub"
  } else {
    normalized
  }
}

///|
fn resolve_relay_sender(options : CliOptions) -> String {
  match options.relay_sender {
    Some(sender) => normalize_relay_sender(sender)
    None =>
      match @nprocess.env().get("BITHUB_RELAY_SENDER") {
        Some(sender) => normalize_relay_sender(sender)
        None =>
          match @nprocess.env().get("USER") {
            Some(user) => normalize_relay_sender(user)
            None => "bithub"
          }
      }
  }
}

///|
fn resolve_relay_auth_token() -> String? {
  match @nprocess.env().get("BIT_RELAY_AUTH_TOKEN") {
    Some(token) => {
      let normalized = token.trim(chars=" \n\r\t").to_string()
      if normalized.length() == 0 {
        None
      } else {
        Some(normalized)
      }
    }
    None => None
  }
}

///|
fn resolve_relay_options(options : CliOptions) -> RelayOptions? {
  match options.relay_url {
    Some(raw_url) =>
      match parse_relay_base_url(raw_url) {
        Some(base_url) => Some({
          base_url,
          room: "main",
          sender: resolve_relay_sender(options),
          auth_token: resolve_relay_auth_token(),
        })
        None => None
      }
    None => None
  }
}

///|
fn json_get_string(
  obj : Map[String, Json],
  key : String,
  fallback : String,
) -> String {
  match obj.get(key) {
    Some(Json::String(value)) => value
    Some(Json::Number(value, ..)) => value.to_string()
    Some(Json::True) => "true"
    Some(Json::False) => "false"
    _ => fallback
  }
}

///|
fn relay_payload_kind(payload : Map[String, Json]) -> String {
  json_get_string(payload, "kind", "")
}

///|
fn relay_payload_url(payload : Map[String, Json]) -> String {
  let primary = json_get_string(payload, "url", "")
  if primary.length() > 0 {
    return primary
  }
  json_get_string(payload, "viewer_url", "")
}

///|
fn relay_payload_name(payload : Map[String, Json], sender : String) -> String {
  let raw = json_get_string(payload, "name", "")
  if raw.trim(chars=" \n\r\t").to_string().length() == 0 {
    sender
  } else {
    raw
  }
}

///|
fn is_bithub_presence_kind(kind : String) -> Bool {
  kind == "bithub.node" ||
  kind == "bithub.viewer" ||
  kind == "bithub.peer"
}

///|
pub fn parse_relay_nodes_from_poll(text : String) -> Array[RelayPeer] {
  let parsed = @json.parse(text) catch { _ => return [] }
  guard parsed is Json::Object(root) else { return [] }
  let latest : Map[String, RelayPeer] = {}
  match root.get("envelopes") {
    Some(Json::Array(items)) =>
      for item in items {
        guard item is Json::Object(envelope) else { continue }
        let raw_sender = json_get_string(envelope, "sender", "")
        if raw_sender.trim(chars=" \n\r\t").to_string().length() == 0 {
          continue
        }
        let sender = normalize_relay_sender(raw_sender)
        guard envelope.get("payload") is Some(Json::Object(payload)) else {
          continue
        }
        let kind = relay_payload_kind(payload)
        if !is_bithub_presence_kind(kind) {
          continue
        }
        let url = relay_payload_url(payload)
        if !is_http_url(url) {
          continue
        }
        let name = relay_payload_name(payload, sender)
        latest[sender] = { sender, url, name }
      }
    _ => ()
  }
  let entries = latest.to_array()
  entries.sort_by(fn(a, b) { String::compare(a.0, b.0) })
  let peers : Array[RelayPeer] = []
  for entry in entries {
    peers.push(entry.1)
  }
  peers
}

///|
extern "js" fn relay_fetch_poll_text_promise(
  base_url : String,
  room : String,
  auth_token : String?,
  ) -> @js.Promise[String] =
  #| (base_url, room, auth_token) => {
  #|   try {
  #|     const base = String(base_url || "").replace(/\/+$/, "");
  #|     const url = new URL(base + "/api/v1/poll");
  #|     url.searchParams.set("room", room || "main");
  #|     url.searchParams.set("after", "0");
  #|     url.searchParams.set("limit", "200");
  #|     const headers = { Accept: "application/json" };
  #|     if (typeof auth_token === "string" && auth_token.length > 0) {
  #|       headers.Authorization = auth_token.startsWith("Bearer ") || auth_token.startsWith("bearer ")
  #|         ? auth_token
  #|         : `Bearer ${auth_token}`;
  #|     }
  #|     return fetch(url.toString(), { method: "GET", headers }).then(async (res) => {
  #|       const text = await res.text();
  #|       if (!res.ok) {
  #|         throw new Error(`HTTP ${res.status}: ${text}`);
  #|       }
  #|       return text;
  #|     });
  #|   } catch (e) {
  #|     const message = e && e.message ? e.message : String(e);
  #|     return Promise.reject(new Error(message));
  #|   }
  #| }

///|
extern "js" fn relay_publish_presence_async(
  base_url : String,
  room : String,
  sender : String,
  viewer_url : String,
  name : String,
  auth_token : String?,
) -> Unit =
  #| (base_url, room, sender, viewer_url, name, auth_token) => {
  #|   try {
  #|     const fs = require("node:fs");
  #|     const crypto = require("node:crypto");
  #|
  #|     function readEnv(key) {
  #|       if (typeof process === "undefined" || !process || !process.env) return "";
  #|       const value = process.env[key];
  #|       return typeof value === "string" ? value : "";
  #|     }
  #|
  #|     function loadRelayPrivateKeyPem() {
  #|       const inlinePem = readEnv("BITHUB_RELAY_SIGN_PRIVATE_KEY_PEM").trim();
  #|       if (inlinePem.length > 0) {
  #|         return inlinePem.replace(/\\n/g, "\n");
  #|       }
  #|       const pemPath = readEnv("BITHUB_RELAY_SIGN_PRIVATE_KEY_FILE").trim();
  #|       if (pemPath.length > 0) {
  #|         try {
  #|           return fs.readFileSync(pemPath, "utf8");
  #|         } catch (_e) {
  #|           return "";
  #|         }
  #|       }
  #|       return "";
  #|     }
  #|
  #|     function canonicalize(value) {
  #|       if (value === null) return "null";
  #|       if (typeof value === "string") return JSON.stringify(value);
  #|       if (typeof value === "number") {
  #|         if (!Number.isFinite(value)) return "null";
  #|         return JSON.stringify(value);
  #|       }
  #|       if (typeof value === "boolean") return value ? "true" : "false";
  #|       if (Array.isArray(value)) {
  #|         return `[${value.map((item) => canonicalize(item)).join(",")}]`;
  #|       }
  #|       if (value && typeof value === "object") {
  #|         const keys = Object.keys(value).sort();
  #|         const parts = keys.map((key) => `${JSON.stringify(key)}:${canonicalize(value[key])}`);
  #|         return `{${parts.join(",")}}`;
  #|       }
  #|       return "null";
  #|     }
  #|
  #|     function computePublishSignature({ sender, room, topic, id, payload }) {
  #|       const pem = loadRelayPrivateKeyPem();
  #|       if (pem.length === 0) return null;
  #|       const privateKey = crypto.createPrivateKey({ key: pem });
  #|       const publicKeyJwk = crypto.createPublicKey(privateKey).export({ format: "jwk" });
  #|       const publicKey = publicKeyJwk && typeof publicKeyJwk.x === "string" ? publicKeyJwk.x : "";
  #|       if (publicKey.length === 0) return null;
  #|       const timestamp = Math.floor(Date.now() / 1000);
  #|       const nonce = typeof crypto.randomUUID === "function"
  #|         ? crypto.randomUUID()
  #|         : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  #|       const payloadCanonical = canonicalize(payload);
  #|       const payloadHash = crypto.createHash("sha256").update(payloadCanonical).digest("hex");
  #|       const message = [
  #|         "v1",
  #|         `sender=${sender}`,
  #|         `room=${room}`,
  #|         `id=${id}`,
  #|         `topic=${topic}`,
  #|         `ts=${timestamp}`,
  #|         `nonce=${nonce}`,
  #|         `payload_sha256=${payloadHash}`,
  #|       ].join("\\n");
  #|       const signature = crypto.sign(null, Buffer.from(message), privateKey).toString("base64url");
  #|       return { publicKey, signature, timestamp, nonce };
  #|     }
  #|
  #|     const base = String(base_url || "").replace(/\/+$/, "");
  #|     let hash = 0;
  #|     for (let i = 0; i < viewer_url.length; i += 1) {
  #|       hash = (hash * 31 + viewer_url.charCodeAt(i)) | 0;
  #|     }
  #|     const eventId = `bithub-${sender}-${(hash >>> 0).toString(16)}`;
  #|     const url = new URL(base + "/api/v1/publish");
  #|     url.searchParams.set("room", room || "main");
  #|     url.searchParams.set("sender", sender);
  #|     url.searchParams.set("topic", "notify");
  #|     url.searchParams.set("id", eventId);
  #|     const headers = { "Content-Type": "application/json" };
  #|     if (typeof auth_token === "string" && auth_token.length > 0) {
  #|       headers.Authorization = auth_token.startsWith("Bearer ") || auth_token.startsWith("bearer ")
  #|         ? auth_token
  #|         : `Bearer ${auth_token}`;
  #|     }
  #|     const payload = {
  #|       payload: {
  #|         kind: "bithub.node",
  #|         url: viewer_url,
  #|         name,
  #|       },
  #|     };
  #|     const signing = computePublishSignature({
  #|       sender,
  #|       room: room || "main",
  #|       topic: "notify",
  #|       id: eventId,
  #|       payload: payload.payload,
  #|     });
  #|     if (signing) {
  #|       headers["x-relay-public-key"] = signing.publicKey;
  #|       headers["x-relay-signature"] = signing.signature;
  #|       headers["x-relay-timestamp"] = String(signing.timestamp);
  #|       headers["x-relay-nonce"] = signing.nonce;
  #|     }
  #|     fetch(url.toString(), {
  #|       method: "POST",
  #|       headers,
  #|       body: JSON.stringify(payload),
  #|     }).catch((e) => {
  #|       const message = e && e.message ? e.message : String(e);
  #|       console.error("bithub relay publish failed:", message);
  #|     });
  #|   } catch (e) {
  #|     const message = e && e.message ? e.message : String(e);
  #|     console.error("bithub relay publish setup failed:", message);
  #|   }
  #| }

///|
fn announce_relay_presence(
  relay : RelayOptions,
  viewer_url : String,
  name : String,
) -> Unit {
  if !is_http_url(viewer_url) {
    return
  }
  relay_publish_presence_async(
    relay.base_url,
    relay.room,
    relay.sender,
    viewer_url,
    name,
    relay.auth_token,
  )
}

///|
async fn fetch_relay_peers(relay : RelayOptions) -> Array[RelayPeer] {
  let text = relay_fetch_poll_text_promise(
    relay.base_url,
    relay.room,
    relay.auth_token,
  )
  .wait() catch {
    msg => {
      println("bithub relay poll error: \{msg}")
      return []
    }
  }
  parse_relay_nodes_from_poll(text)
}

///|
fn default_p2p_command_template() -> String {
  "npx --yes localtunnel --port {port}"
}

///|
fn resolve_p2p_command_template(options : CliOptions) -> String {
  match options.p2p_command_template {
    Some(cmd) => cmd
    None =>
      match @nprocess.env().get("BITHUB_P2P_CMD") {
        Some(env_cmd) => env_cmd
        None => default_p2p_command_template()
      }
  }
}

///|
extern "js" fn chunk_to_string(data : @js.Any) -> String =
  #|(data) => {
  #|  if (typeof data === "string") return data;
  #|  if (data && typeof data.toString === "function") return data.toString();
  #|  return String(data ?? "");
  #|}

///|
fn start_p2p_tunnel(
  options : CliOptions,
  host : String,
  on_public_url : (String) -> Unit,
) -> @nchild.ChildProcess? {
  if !options.enable_p2p {
    return None
  }
  let local_url = "http://\{host}:\{options.port}"
  let template = resolve_p2p_command_template(options)
  let command = render_p2p_command(template, local_url, options.port)
  println("bithub p2p: starting tunnel")
  println("bithub p2p command: \{command}")

  let child = @nchild.spawn(command, shell=true)
  child.on_stdout_data(fn(data) {
    let chunk = chunk_to_string(data)
    if chunk.length() > 0 {
      ignore(@nprocess.stdout().write(@js.any(chunk)))
    }
    match extract_first_http_url(chunk) {
      Some(url) => {
        println("bithub public: \{url}")
        on_public_url(url)
      }
      None => ()
    }
  })
  child.on_stderr_data(fn(data) {
    let chunk = chunk_to_string(data)
    if chunk.length() > 0 {
      ignore(@nprocess.stderr().write(@js.any(chunk)))
    }
    match extract_first_http_url(chunk) {
      Some(url) => {
        println("bithub public: \{url}")
        on_public_url(url)
      }
      None => ()
    }
  })
  child.on_error(fn(_err) {
    ignore(
      @nprocess.stderr().write(@js.any("bithub p2p error: spawn failed\n")),
    )
  })
  child.on_close(fn(code, signal) {
    let code_text = match code {
      Some(c) => c.to_string()
      None => "null"
    }
    let signal_text = signal.unwrap_or("none")
    println("bithub p2p: stopped (code=\{code_text}, signal=\{signal_text})")
  })

  @nprocess.on("SIGINT", fn() { ignore(child.kill()) })
  @nprocess.on("SIGTERM", fn() { ignore(child.kill()) })

  Some(child)
}

///|
fn route_repo_response(state : RepoState, raw_url : String) -> PageResponse {
  if raw_url == "/" || raw_url.has_prefix("/?") || raw_url.has_prefix("/#") {
    return state.render_root()
  }
  if raw_url == "/issues" ||
    raw_url.has_prefix("/issues?") ||
    raw_url.has_prefix("/issues#") {
    return state.render_issues()
  }
  if raw_url.has_prefix("/blob/") {
    let rel_path = extract_blob_path(raw_url)
    return state.render_blob(rel_path)
  }
  {
    status: 404,
    html: state.render_layout("(not found)", "<p>Route not found.</p>"),
  }
}

///|
fn parse_catalog_repo_route(raw_url : String) -> (String, String)? {
  if !raw_url.has_prefix("/repo/") {
    return None
  }
  let rest = String::unsafe_substring(raw_url, start=6, end=raw_url.length())
  if rest.length() == 0 {
    return None
  }

  let mut repo_end = rest.length()
  for idx, c in rest {
    if c == '/' || c == '?' || c == '#' {
      repo_end = idx
      break
    }
  }
  if repo_end == 0 {
    return None
  }

  let repo_id = String::unsafe_substring(rest, start=0, end=repo_end)
  let route_prefix = "/repo/" + repo_id
  let suffix = if raw_url.length() > route_prefix.length() {
    String::unsafe_substring(
      raw_url,
      start=route_prefix.length(),
      end=raw_url.length(),
    )
  } else {
    ""
  }
  let normalized_suffix = if suffix.length() == 0 {
    "/"
  } else if suffix.has_prefix("?") || suffix.has_prefix("#") {
    "/" + suffix
  } else {
    suffix
  }
  Some((repo_id, normalized_suffix))
}

///|
fn find_catalog_repo(
  repos : Array[CatalogRepo],
  repo_id : String,
) -> CatalogRepo? {
  for repo in repos {
    if repo.id == repo_id {
      return Some(repo)
    }
  }
  None
}

///|
fn render_catalog_html(
  repos : Array[CatalogRepo],
  title : String,
  message? : String = "",
) -> String {
  let list = StringBuilder::new()
  if repos.length() == 0 {
    list.write_string("<p>No repositories in catalog.</p>")
  } else {
    list.write_string("<ul>")
    for repo in repos {
      list.write_string(
        "<li><a href=\"/repo/" +
        escape_html(repo.id) +
        "\">" +
        escape_html(repo.name) +
        "</a> <code>" +
        escape_html(shorten_home_prefix(repo.root)) +
        "</code></li>",
      )
    }
    list.write_string("</ul>")
  }

  let body = StringBuilder::new()
  body.write_string("<!doctype html><html><head><meta charset=\"utf-8\">")
  body.write_string("<title>bithub catalog</title>")
  body.write_string(
    "<style>:root{color-scheme:light dark;--bg:#f8fafc;--text:#0f172a;--panel:#ffffff;--border:#d1d5db;--link:#1d4ed8;}@media (prefers-color-scheme: dark){:root{--bg:#0b1220;--text:#dbe7ff;--panel:#111a2e;--border:#2a3653;--link:#7cb3ff;}}body{margin:0;padding:24px;font-family:ui-sans-serif,system-ui,sans-serif;background:var(--bg);color:var(--text);}main{max-width:980px;margin:0 auto;background:var(--panel);padding:16px;border:1px solid var(--border);border-radius:8px;}a{color:var(--link);}code{font-family:ui-monospace,Menlo,monospace;}</style>",
  )
  body.write_string("</head><body><main>")
  body.write_string("<h1>" + escape_html(title) + "</h1>")
  if message.length() > 0 {
    body.write_string("<p>" + escape_html(message) + "</p>")
  }
  body.write_string(list.to_string())
  body.write_string("</main></body></html>")
  body.to_string()
}

///|
fn route_catalog_response(
  repos : Array[CatalogRepo],
  raw_url : String,
) -> PageResponse {
  if raw_url == "/" || raw_url.has_prefix("/?") || raw_url.has_prefix("/#") {
    return { status: 200, html: render_catalog_html(repos, "bithub catalog") }
  }
  match parse_catalog_repo_route(raw_url) {
    Some((repo_id, repo_raw_url)) =>
      match find_catalog_repo(repos, repo_id) {
        Some(repo) => route_repo_response(repo.state, repo_raw_url)
        None =>
          {
            status: 404,
            html: render_catalog_html(
              repos,
              "bithub catalog",
              message="Unknown repository id: " + repo_id,
            ),
          }
      }
    None =>
      {
        status: 404,
        html: render_catalog_html(
          repos,
          "bithub catalog",
          message="Route not found.",
        ),
      }
  }
}

///|
fn relay_find_char(s : String, target : Char) -> Int {
  let mut idx = 0
  for c in s {
    if c == target {
      return idx
    }
    idx += 1
  }
  -1
}

///|
fn relay_strip_query_and_hash(path : String) -> String {
  let query_pos = relay_find_char(path, '?')
  let hash_pos = relay_find_char(path, '#')
  let mut end = path.length()
  if query_pos >= 0 && query_pos < end {
    end = query_pos
  }
  if hash_pos >= 0 && hash_pos < end {
    end = hash_pos
  }
  if end < path.length() {
    String::unsafe_substring(path, start=0, end~)
  } else {
    path
  }
}

///|
fn has_relay_route_prefix(raw_url : String) -> Bool {
  let plain = relay_strip_query_and_hash(raw_url)
  plain == "/relay" || plain == "/relay/" || plain.has_prefix("/relay/")
}

///|
fn render_relay_catalog_html(
  relay : RelayOptions,
  peers : Array[RelayPeer],
  message? : String = "",
) -> String {
  let list = StringBuilder::new()
  if peers.length() == 0 {
    list.write_string("<p>No relay nodes published yet.</p>")
  } else {
    list.write_string("<ul>")
    for peer in peers {
      list.write_string(
        "<li><strong>" +
        escape_html(peer.sender) +
        "</strong> : " +
        "<a href=\"" +
        escape_html(peer.url) +
        "\">" +
        escape_html(peer.name) +
        "</a> " +
        "<code>" +
        escape_html(peer.url) +
        "</code></li>",
      )
    }
    list.write_string("</ul>")
  }

  let body = StringBuilder::new()
  body.write_string("<!doctype html><html><head><meta charset=\"utf-8\">")
  body.write_string("<title>bithub relay</title>")
  body.write_string(
    "<style>:root{color-scheme:light dark;--bg:#f8fafc;--text:#0f172a;--panel:#ffffff;--border:#d1d5db;--link:#1d4ed8;}@media (prefers-color-scheme: dark){:root{--bg:#0b1220;--text:#dbe7ff;--panel:#111a2e;--border:#2a3653;--link:#7cb3ff;}}body{margin:0;padding:24px;font-family:ui-sans-serif,system-ui,sans-serif;background:var(--bg);color:var(--text);}main{max-width:980px;margin:0 auto;background:var(--panel);padding:16px;border:1px solid var(--border);border-radius:8px;}a{color:var(--link);}code{font-family:ui-monospace,Menlo,monospace;overflow-wrap:anywhere;}</style>",
  )
  body.write_string("</head><body><main>")
  body.write_string("<h1>bithub relay nodes</h1>")
  body.write_string(
    "<p><a href=\"/\">back to viewer</a> | relay: <code>" +
    escape_html(relay.base_url) +
    "</code></p>",
  )
  if message.length() > 0 {
    body.write_string("<p>" + escape_html(message) + "</p>")
  }
  body.write_string(list.to_string())
  body.write_string("</main></body></html>")
  body.to_string()
}

///|
async fn route_relay_response(
  relay : RelayOptions,
  raw_url : String,
) -> PageResponse {
  let plain = relay_strip_query_and_hash(raw_url)
  let peers = fetch_relay_peers(relay)
  if plain == "/relay" || plain == "/relay/" {
    return {
      status: 200,
      html: render_relay_catalog_html(relay, peers),
    }
  }
  {
    status: 404,
    html: render_relay_catalog_html(relay, peers, message="Route not found."),
  }
}

///|
priv enum AppState {
  Single(RepoState)
  Catalog(Array[CatalogRepo])
}

///|
fn route_response(app_state : AppState, raw_url : String) -> PageResponse {
  match app_state {
    Single(state) => route_repo_response(state, raw_url)
    Catalog(repos) => route_catalog_response(repos, raw_url)
  }
}

///|
fn configure_sol_app(
  app : @mars.Server,
  app_state : AppState,
  relay_options : RelayOptions?,
) -> Unit {
  app.get(
    "*",
    @mars.handler(async fn(ctx) {
      let raw_url = ctx.path()
      match relay_options {
        Some(relay) =>
          if has_relay_route_prefix(raw_url) {
            let relay_response = route_relay_response(relay, raw_url)
            ctx.html(relay_response.html, status=relay_response.status)
            return
          }
        None => ()
      }
      let response = route_response(app_state, raw_url)
      ctx.html(response.html, status=response.status)
    }),
  )
}

///|
pub extern "js" fn ensure_sol_reschedule_symbol() -> Unit =
  #| () => {
  #|   const key = "moonbitlang$async$internal$event_loop$$reschedule";
  #|   if (typeof globalThis[key] !== "function") {
  #|     globalThis[key] = () => {};
  #|   }
  #| }

///|
fn relay_announce_name(app_state : AppState) -> String {
  match app_state {
    Single(state) => derive_catalog_name(state.root)
    Catalog(_) => "catalog"
  }
}

///|
fn main {
  let options = parse_args()
  let app_state = match options.catalog_path {
    Some(path) => Catalog(load_catalog_repos(path))
    None => Single(RepoState::new(options.repo))
  }
  let host = "127.0.0.1"
  let relay_options = resolve_relay_options(options)
  if options.relay_url is Some(raw_relay_url) && relay_options is None {
    println("bithub relay: unsupported relay url: \{raw_relay_url}")
  }
  let announce_name = relay_announce_name(app_state)
  let local_url = "http://\{host}:\{options.port}"
  match relay_options {
    Some(relay) => announce_relay_presence(relay, local_url, announce_name)
    None => ()
  }
  let _p2p_tunnel = start_p2p_tunnel(
    options,
    host,
    fn(public_url) {
      match relay_options {
        Some(relay) => announce_relay_presence(relay, public_url, announce_name)
        None => ()
      }
    },
  )
  ensure_sol_reschedule_symbol()
  @sol.run(
    fn(app) {
      configure_sol_app(app, app_state, relay_options)
      println("bithub: http://\{host}:\{options.port}/")
      match app_state {
        Single(state) => println("repo: \{state.root}")
        Catalog(repos) => println("catalog repos: \{repos.length()}")
      }
      match relay_options {
        Some(_relay) => println("relay: http://\{host}:\{options.port}/relay")
        None => ()
      }
    },
    port=options.port,
  )
}
