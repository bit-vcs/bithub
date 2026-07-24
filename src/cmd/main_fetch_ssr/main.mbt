///|
fn parse_port(raw : String) -> Int {
  let parsed = @string.parse_int(raw) catch { _ => 4175 }
  if parsed > 0 {
    parsed
  } else {
    4175
  }
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
extern "js" fn start_node_worker_server(
  fetch_handler : (
    @mars.JsRequest,
    @mars.JsEnv,
    @mars.JsExecCtx,
  ) -> @js_async.Promise[@mars.JsResponse],
  port : Int,
) -> Unit =
  #| (fetch_handler, port) => {
  #|   const http = require("node:http");
  #|   const host = "127.0.0.1";
  #|
  #|   const readBody = (req) =>
  #|     new Promise((resolve, reject) => {
  #|       const chunks = [];
  #|       req.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
  #|       req.on("end", () => {
  #|         if (chunks.length === 0) {
  #|           resolve(undefined);
  #|           return;
  #|         }
  #|         resolve(Buffer.concat(chunks));
  #|       });
  #|       req.on("error", reject);
  #|     });
  #|
  #|   const normalizeHeaders = (headers) => {
  #|     const out = {};
  #|     for (const [key, value] of Object.entries(headers ?? {})) {
  #|       if (Array.isArray(value)) {
  #|         out[key] = value.join(", ");
  #|       } else if (typeof value === "string") {
  #|         out[key] = value;
  #|       }
  #|     }
  #|     return out;
  #|   };
  #|
  #|   const server = http.createServer(async (req, res) => {
  #|     try {
  #|       const method = req.method ?? "GET";
  #|       const url = new URL(req.url ?? "/", `http://${host}:${port}`);
  #|       const headers = normalizeHeaders(req.headers);
  #|       const body = method === "GET" || method === "HEAD" ? undefined : await readBody(req);
  #|
  #|       const request = new Request(url.toString(), {
  #|         method,
  #|         headers,
  #|         body,
  #|       });
  #|       const env = {};
  #|       const execCtx = {
  #|         waitUntil(promise) {
  #|           if (promise && typeof promise.catch === "function") {
  #|             promise.catch(() => {});
  #|           }
  #|         },
  #|       };
  #|
  #|       const response = await fetch_handler(request, env, execCtx);
  #|       res.statusCode = response.status;
  #|       for (const [key, value] of response.headers.entries()) {
  #|         res.setHeader(key, value);
  #|       }
  #|       if (method === "HEAD") {
  #|         res.end();
  #|         return;
  #|       }
  #|       const raw = await response.arrayBuffer();
  #|       res.end(Buffer.from(raw));
  #|     } catch (error) {
  #|       res.statusCode = 500;
  #|       res.setHeader("content-type", "text/plain; charset=utf-8");
  #|       const message = error instanceof Error ? error.stack || error.message : String(error);
  #|       res.end(message);
  #|     }
  #|   });
  #|
  #|   server.listen(port, host, () => {
  #|     console.log(`main_fetch_ssr: http://${host}:${port}/`);
  #|   });
  #| }

///|
fn main {
  let argv = @nprocess.argv()
  let port = if argv.length() > 2 { parse_port(argv[2]) } else { 4175 }
  ensure_sol_reschedule_symbol()
  start_node_worker_server(@main_cmd.fetch, port)
}

///|
test "parse_port fallback and valid value" {
  assert_eq(parse_port("9001"), 9001)
  assert_eq(parse_port("-1"), 4175)
  assert_eq(parse_port("abc"), 4175)
}
