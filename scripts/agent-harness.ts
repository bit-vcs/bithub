/**
 * Coding agent harness with real tool execution.
 *
 * Tools:
 *   read_file(path)          - Read a file from disk
 *   write_file(path, content) - Write a file to disk
 *   list_dir(path)           - List directory contents
 *   run(command)             - Run shell command (build, test, etc.)
 *   search(query)            - Grep codebase
 *   bithub_post(path, data)  - Call bithub API
 *   done(summary)            - Signal task completion
 *
 * Usage:
 *   ISSUE_ID=1 npx tsx scripts/agent-harness.ts
 */

import { execSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";

const BITHUB_URL = process.env.BITHUB_URL || "http://127.0.0.1:4174";
const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY!;
const MODEL = process.env.MODEL || "anthropic/claude-sonnet-4";
const ISSUE_ID = process.env.ISSUE_ID;
const TASK = process.env.TASK; // free-form task if no issue
const AGENT_TOKEN = process.env.AGENT_TOKEN || "tok-bob";
const AGENT_NAME = process.env.AGENT_NAME || "agent-bob";
const REPO_ROOT = process.env.REPO_ROOT || process.cwd();
const MAX_TURNS = parseInt(process.env.MAX_TURNS || "15", 10);

if (!OPENROUTER_API_KEY) {
  console.error("OPENROUTER_API_KEY required");
  process.exit(1);
}

// ---- Tool definitions ----

const TOOLS = [
  {
    type: "function" as const,
    function: {
      name: "read_file",
      description: "Read a file from the repository. Returns the file content as text. Use start_line/end_line to read a specific range of a large file.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "File path relative to repo root" },
          start_line: { type: "number", description: "Start line (1-based, inclusive). Omit to read from beginning." },
          end_line: { type: "number", description: "End line (1-based, inclusive). Omit to read to end." },
        },
        required: ["path"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "write_file",
      description: "Write content to a file. Creates parent directories if needed.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "File path relative to repo root" },
          content: { type: "string", description: "File content to write" },
        },
        required: ["path", "content"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "list_dir",
      description: "List files and directories in a path.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "Directory path relative to repo root (empty for root)" },
        },
        required: ["path"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "run",
      description: "Run a shell command. Use for: moon check, moon test, moon build, pnpm test:e2e, etc. Returns stdout+stderr.",
      parameters: {
        type: "object",
        properties: {
          command: { type: "string", description: "Shell command to execute" },
        },
        required: ["command"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "patch_file",
      description: "Replace, insert, or delete lines in a file. Specify start_line and end_line for the range to replace (1-based). Set content to empty string to delete lines. To insert before a line, set start_line = end_line = target_line and provide new content followed by original line.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "File path relative to repo root" },
          start_line: { type: "number", description: "First line to replace (1-based, inclusive)" },
          end_line: { type: "number", description: "Last line to replace (1-based, inclusive)" },
          content: { type: "string", description: "Replacement content (lines joined by newlines). Empty string to delete." },
        },
        required: ["path", "start_line", "end_line", "content"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "search",
      description: "Search for text in the codebase using grep. Returns matching lines with file paths.",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string", description: "Text to search for" },
          glob: { type: "string", description: "File glob pattern (e.g., '*.mbt', '*.ts')" },
        },
        required: ["query"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "bithub_post",
      description: "Make a POST request to the bithub API. Use for creating issues, PRs, comments.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "API path (e.g., /api/issues, /api/pulls)" },
          data: { type: "object", description: "JSON body" },
        },
        required: ["path", "data"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "done",
      description: "Signal that the task is complete. Call this when finished.",
      parameters: {
        type: "object",
        properties: {
          summary: { type: "string", description: "Brief summary of what was done" },
        },
        required: ["summary"],
      },
    },
  },
];

// ---- Tool execution ----

function executeTool(name: string, args: Record<string, unknown>): string {
  try {
    switch (name) {
      case "read_file": {
        const filePath = path.resolve(REPO_ROOT, args.path as string);
        if (!fs.existsSync(filePath)) return `Error: file not found: ${args.path}`;
        const content = fs.readFileSync(filePath, "utf-8");
        const lines = content.split("\n");
        const startLine = (args.start_line as number) || 1;
        const endLine = (args.end_line as number) || lines.length;
        const selected = lines.slice(startLine - 1, endLine);
        const result = selected.map((l, i) => `${startLine + i}| ${l}`).join("\n");
        if (result.length > 12000) {
          return result.slice(0, 12000) + `\n... (truncated, ${lines.length} total lines)`;
        }
        return result + `\n(${lines.length} total lines)`;
      }
      case "write_file": {
        const filePath = path.resolve(REPO_ROOT, args.path as string);
        fs.mkdirSync(path.dirname(filePath), { recursive: true });
        fs.writeFileSync(filePath, args.content as string, "utf-8");
        return `Written ${(args.content as string).length} chars to ${args.path}`;
      }
      case "list_dir": {
        const dirPath = path.resolve(REPO_ROOT, (args.path as string) || ".");
        if (!fs.existsSync(dirPath)) return `Error: directory not found: ${args.path}`;
        const entries = fs.readdirSync(dirPath, { withFileTypes: true });
        return entries
          .filter((e) => !e.name.startsWith(".") && e.name !== "node_modules" && e.name !== "_build" && e.name !== ".mooncakes")
          .map((e) => `${e.isDirectory() ? "[dir]" : "[file]"} ${e.name}`)
          .join("\n");
      }
      case "patch_file": {
        const filePath = path.resolve(REPO_ROOT, args.path as string);
        if (!fs.existsSync(filePath)) return `Error: file not found: ${args.path}`;
        const lines = fs.readFileSync(filePath, "utf-8").split("\n");
        const startLine = (args.start_line as number) || 1;
        const endLine = (args.end_line as number) || startLine;
        const newContent = args.content as string;
        const before = lines.slice(0, startLine - 1);
        const after = lines.slice(endLine);
        const replacement = newContent.length > 0 ? newContent.split("\n") : [];
        const result = [...before, ...replacement, ...after];
        fs.writeFileSync(filePath, result.join("\n"), "utf-8");
        const diff = endLine - startLine + 1;
        return `Patched ${args.path}: replaced lines ${startLine}-${endLine} (${diff} lines) with ${replacement.length} lines. File now has ${result.length} lines.`;
      }
      case "run": {
        const cmd = args.command as string;
        // Safety: block dangerous commands
        if (/rm\s+-rf|rmdir|del\s+\/|format/i.test(cmd)) {
          return "Error: dangerous command blocked";
        }
        try {
          const output = execSync(cmd, {
            cwd: REPO_ROOT,
            timeout: 60_000,
            encoding: "utf-8",
            maxBuffer: 1024 * 1024,
            env: { ...process.env, FORCE_COLOR: "0" },
          });
          const trimmed = output.slice(-4000); // Last 4000 chars
          return trimmed;
        } catch (err: unknown) {
          const e = err as { stdout?: string; stderr?: string; status?: number };
          const out = ((e.stdout || "") + "\n" + (e.stderr || "")).slice(-4000);
          return `Command failed (exit ${e.status}):\n${out}`;
        }
      }
      case "search": {
        const query = args.query as string;
        const glob = (args.glob as string) || "";
        const globArg = glob ? `--include='${glob}'` : "";
        try {
          const output = execSync(
            `grep -rn ${globArg} --exclude-dir=node_modules --exclude-dir=_build --exclude-dir=.mooncakes --exclude-dir=.git --exclude-dir=.bithub --exclude-dir=.wrangler --exclude-dir=test-results ${JSON.stringify(query)} src/`,
            { cwd: REPO_ROOT, timeout: 10_000, encoding: "utf-8", maxBuffer: 512 * 1024 },
          );
          const lines = output.split("\n").slice(0, 30);
          return lines.join("\n") + (output.split("\n").length > 30 ? "\n... (more results)" : "");
        } catch {
          return "No matches found";
        }
      }
      case "bithub_post": {
        // Synchronous fetch via execSync
        const apiPath = args.path as string;
        const data = JSON.stringify(args.data);
        try {
          const output = execSync(
            `curl -s -X POST "${BITHUB_URL}${apiPath}" -H "Authorization: Bearer ${AGENT_TOKEN}" -H "Content-Type: application/json" -d '${data.replace(/'/g, "'\\''")}'`,
            { cwd: REPO_ROOT, timeout: 10_000, encoding: "utf-8" },
          );
          return output;
        } catch (err: unknown) {
          return `API call failed: ${(err as Error).message}`;
        }
      }
      case "done":
        return `DONE: ${args.summary}`;
      default:
        return `Unknown tool: ${name}`;
    }
  } catch (err: unknown) {
    return `Tool error: ${(err as Error).message}`;
  }
}

// ---- LLM with tool use ----

interface Message {
  role: "system" | "user" | "assistant" | "tool";
  content: string | null;
  tool_calls?: Array<{
    id: string;
    type: "function";
    function: { name: string; arguments: string };
  }>;
  tool_call_id?: string;
}

async function llmWithTools(messages: Message[]): Promise<{
  message: Message;
  done: boolean;
  summary: string;
}> {
  const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENROUTER_API_KEY}`,
    },
    body: JSON.stringify({
      model: MODEL,
      messages,
      tools: TOOLS,
      max_tokens: 4096,
      temperature: 0.2,
    }),
  });

  const data = (await res.json()) as {
    choices?: Array<{
      message?: Message;
      finish_reason?: string;
    }>;
    error?: { message?: string };
  };

  if (data.error) throw new Error(`LLM: ${data.error.message}`);
  const msg = data.choices?.[0]?.message;
  if (!msg) throw new Error("No response from LLM");

  // Check if the model wants to call tools
  if (msg.tool_calls && msg.tool_calls.length > 0) {
    messages.push(msg);

    let isDone = false;
    let summary = "";

    for (const call of msg.tool_calls) {
      let args: Record<string, unknown>;
      try {
        args = JSON.parse(call.function.arguments);
      } catch {
        console.log(`  → ${call.function.name}(PARSE ERROR: ${call.function.arguments.slice(0, 100)})`);
        messages.push({
          role: "tool",
          content: "Error: failed to parse tool arguments. Try again with simpler content.",
          tool_call_id: call.id,
        });
        continue;
      }
      console.log(`  → ${call.function.name}(${JSON.stringify(args).slice(0, 100)})`);

      const result = executeTool(call.function.name, args);
      console.log(`    ${result.slice(0, 150).replace(/\n/g, " ")}${result.length > 150 ? "..." : ""}`);

      messages.push({
        role: "tool",
        content: result,
        tool_call_id: call.id,
      });

      if (call.function.name === "done") {
        isDone = true;
        summary = args.summary as string;
      }
    }

    return { message: msg, done: isDone, summary };
  }

  // No tool calls - just a text response
  messages.push(msg);
  console.log(`  Agent: ${(msg.content || "").slice(0, 200)}`);

  // If the model stops without calling done, treat as done
  return { message: msg, done: true, summary: msg.content || "completed" };
}

// ---- Main agent loop ----

async function main() {
  console.log("=== Coding Agent Harness ===");
  console.log(`Model: ${MODEL}`);
  console.log(`Repo: ${REPO_ROOT}`);
  console.log(`Bithub: ${BITHUB_URL}`);

  // Determine task
  let taskDescription: string;
  if (ISSUE_ID) {
    // Fetch issue from bithub - extract meaningful content
    const html = await (await fetch(`${BITHUB_URL}/issues/${ISSUE_ID}`)).text();
    // Extract title from <h1>
    const titleMatch = html.match(/<h1[^>]*>(.*?)<\/h1>/s);
    const title = titleMatch ? titleMatch[1].replace(/<[^>]*>/g, "").trim() : "";
    // Extract body from region aria-label="issue body"
    const bodyMatch = html.match(/aria-label="issue body"[^>]*>([\s\S]*?)(?=<h2|<footer)/);
    const body = bodyMatch ? bodyMatch[1].replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim() : "";
    // Extract metadata
    const metaMatch = html.match(/state:.*?(?=<)/);
    const meta = metaMatch ? metaMatch[0].trim() : "";
    taskDescription = `Issue #${ISSUE_ID}: ${title}\n${meta}\n\n${body}`.slice(0, 1200);
    console.log(`Task: Issue #${ISSUE_ID}`);
  } else if (TASK) {
    taskDescription = TASK;
    console.log(`Task: ${TASK.slice(0, 100)}`);
  } else {
    console.error("Set ISSUE_ID or TASK environment variable");
    process.exit(1);
  }
  console.log("");

  const messages: Message[] = [
    {
      role: "system",
      content: `You are ${AGENT_NAME}, a coding agent working on the bithub project.
bithub is a GitHub-like platform built in MoonBit with Playwright E2E tests.

## Workflow (BE FAST — minimize exploration, maximize action)
1. Read the task — it contains specific file paths and line numbers
2. Go DIRECTLY to the mentioned files (do NOT explore unrelated dirs)
3. Use patch_file for line edits, write_file for new files
4. Run "moon check --target js" to verify
5. Run "moon test --target js" to confirm
6. Call done() immediately when tests pass

## Key Commands
- moon check --target js     (type check - FAST, run after every edit)
- moon test --target js       (unit tests)
- moon build --target js      (full build)

## File Structure
- src/core/*.mbt             (data layer: Storage, ApiState)
- src/core/*_test.mbt        (black-box unit tests)
- src/adapters/mars_http/    (HTTP server, routing, rendering)
- src/cmd/                   (entry points)
- e2e/*.spec.ts              (Playwright E2E tests)

## MoonBit Syntax Rules (CRITICAL)
- Blocks separated by \`///|\` — every top-level item starts with \`///|\`
- \`fn\` is private, \`pub fn\` is public. Tests in *_test.mbt can only call pub functions.
- Type parameters: \`fn[T] identity(val: T) -> T\` (NOT \`fn identity[T]\`)
- Error handling: \`fn parse(s: String) -> Int raise Error\` (NOT \`-> Int!Error\`)
- No \`return\` needed — last expression is the return value
- No \`++\`/\`--\` — use \`i += 1\`
- \`for i in 0..<n { ... }\` for range loops
- Variables: lower_snake_case. Types: UpperCamelCase.
- \`let mut\` only for reassignment, not for Array.push() etc.
- String interpolation: \`"hello \\{name}"\` (backslash-brace, no \`$\`)
- Multi-line strings: \`#|line 1\\n#|line 2\`
- Methods require Type:: prefix: \`pub fn ApiState::search(...)\`
- Snapshot tests: \`inspect(value, content="expected")\`, update with \`moon test -u\`
- \`match\` exhaustiveness required. Use \`_\` for wildcard.
- Trait impl: \`pub impl Storage for MyType with get(self, key) { ... }\`

## Common Mistakes to Avoid
- Don't use uppercase for variables/functions
- Don't forget \`///|\` before each top-level block
- Don't use \`try\` for error propagation — it's automatic
- Don't use \`await\` — MoonBit has no await keyword
- Don't use sed/awk to edit files — use write_file tool
- Don't rewrite entire large files — use read_file with line ranges, then write only the changed portion

## Editing Strategy for Large Files
1. read_file(path) to see total line count
2. read_file(path, start_line=X, end_line=Y) to read specific sections
3. search(query) to find the exact location
4. Use patch_file(path, start_line, end_line, content) to replace specific lines
   - To change "fn foo" to "pub fn foo" on line 42: patch_file(path, 42, 42, "pub fn foo")
   - To delete lines 10-15: patch_file(path, 10, 15, "")
   - To insert after line 20: patch_file(path, 21, 20, "new line content") [start > end = insert]
5. For NEW files, use write_file

## Test Patterns
- Black-box tests in *_test.mbt: \`test "name" { inspect(fn_call(), content="expected") }\`
- Use \`@json.inspect()\` for complex values
- Run \`moon test --target js -f filename.mbt\` to test a specific file`,
    },
    {
      role: "user",
      content: taskDescription,
    },
  ];

  // Agent loop
  for (let turn = 0; turn < MAX_TURNS; turn++) {
    console.log(`\n--- Turn ${turn + 1}/${MAX_TURNS} ---`);
    const { done, summary } = await llmWithTools(messages);

    if (done) {
      console.log(`\n=== Agent finished ===`);
      console.log(`Summary: ${summary}`);
      break;
    }
  }

  if (messages.length >= MAX_TURNS * 2) {
    console.log("\n=== Max turns reached ===");
  }
}

main().catch((err) => {
  console.error("Agent failed:", err);
  process.exit(1);
});
