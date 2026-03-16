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
      description: "Read a file from the repository. Returns the file content as text.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "File path relative to repo root" },
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
        // Limit output to avoid token explosion
        if (content.length > 8000) {
          return content.slice(0, 8000) + `\n... (truncated, ${content.length} total chars)`;
        }
        return content;
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
            `grep -rn ${globArg} --exclude-dir=node_modules --exclude-dir=_build --exclude-dir=.mooncakes --exclude-dir=.git --exclude-dir=.bithub ${JSON.stringify(query)} .`,
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
      const args = JSON.parse(call.function.arguments);
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
    // Fetch issue from bithub
    const html = await (await fetch(`${BITHUB_URL}/issues/${ISSUE_ID}`)).text();
    const text = html.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
    taskDescription = `Implement bithub issue #${ISSUE_ID}:\n${text.slice(0, 600)}`;
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

Your workflow:
1. Read the task/issue carefully
2. Explore the codebase to understand the current state
3. Make targeted changes to implement the task
4. Run tests to verify your changes work
5. If tests fail, read the errors and fix them
6. When done, create a PR via bithub API and call done()

Key commands:
- moon check --target js     (type check)
- moon test --target js       (unit tests)
- moon build --target js      (build)

File structure:
- src/core/*.mbt             (data layer: Storage, ApiState)
- src/adapters/mars_http/    (HTTP server, routing, rendering)
- src/cmd/                   (entry points)
- e2e/*.spec.ts              (Playwright E2E tests)

Code style: MoonBit with ///| block separators. Use existing patterns.

IMPORTANT:
- Make minimal, targeted changes. Don't rewrite entire files.
- Use write_file to modify files, NOT sed or other shell commands.
- When editing, read the file first, modify the content in your response, then write_file.
- After making changes, always run "moon check --target js" to verify.
- If a function is private (fn), you may need to make it pub (pub fn) to test it from _test.mbt.
- When appending to a test file, read it first, then write the full content back with your additions.`,
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
