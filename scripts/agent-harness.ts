/**
 * Coding agent harness v2.
 *
 * Tools:
 *   read_file(path, start_line?, end_line?)  - Read file with line numbers
 *   write_file(path, content)                - Create/overwrite file
 *   patch_file(path, start_line, end_line, content) - Edit specific lines
 *   list_dir(path)                           - List directory
 *   run(command)                             - Shell command (build, test)
 *   search(query, glob?)                     - Grep codebase
 *   moon_ide(subcommand)                     - moon ide peek-def/outline/find-references
 *   diff()                                   - Show current git diff
 *   done(summary)                            - Complete task
 *
 * Features:
 *   - Auto-retry on moon check failure (feeds errors back to LLM)
 *   - git stash rollback on failure
 *   - Whitebox test awareness (_wbtest.mbt for private function testing)
 *   - moon ide for semantic navigation
 *
 * Usage:
 *   ISSUE_ID=1 npx tsx scripts/agent-harness.ts
 *   TASK="add X" npx tsx scripts/agent-harness.ts
 */

import { execSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";

const BITHUB_URL = process.env.BITHUB_URL || "http://127.0.0.1:4174";
const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY!;
const MODEL = process.env.MODEL || "anthropic/claude-sonnet-4";
const ISSUE_ID = process.env.ISSUE_ID;
const TASK = process.env.TASK;
const AGENT_TOKEN = process.env.AGENT_TOKEN || "tok-bob";
const AGENT_NAME = process.env.AGENT_NAME || "agent-bob";
const REPO_ROOT = process.env.REPO_ROOT || process.cwd();
const MAX_TURNS = parseInt(process.env.MAX_TURNS || "20", 10);

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
      description: "Read file with line numbers. Use start_line/end_line for large files.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "File path relative to repo root" },
          start_line: { type: "number", description: "Start line (1-based)" },
          end_line: { type: "number", description: "End line (1-based)" },
        },
        required: ["path"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "write_file",
      description: "Create or overwrite a file. Use for NEW files only. For editing existing files, use patch_file.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "File path" },
          content: { type: "string", description: "Full file content" },
        },
        required: ["path", "content"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "patch_file",
      description: "Replace lines start_line..end_line with new content. To delete lines, pass empty content. To insert, set start_line = end_line + 1.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "File path" },
          start_line: { type: "number", description: "First line to replace (1-based)" },
          end_line: { type: "number", description: "Last line to replace (1-based)" },
          content: { type: "string", description: "Replacement text (empty to delete)" },
        },
        required: ["path", "start_line", "end_line", "content"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "list_dir",
      description: "List directory contents.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "Directory path (empty for root)" },
        },
        required: ["path"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "run",
      description: "Run shell command. For build/test: moon check --target js, moon test --target js, moon build --target js.",
      parameters: {
        type: "object",
        properties: {
          command: { type: "string", description: "Command to execute" },
        },
        required: ["command"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "search",
      description: "Grep source code. Returns file:line:content.",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string", description: "Search text" },
          glob: { type: "string", description: "File pattern (e.g. *.mbt)" },
        },
        required: ["query"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "moon_ide",
      description: "Semantic code navigation. Subcommands: 'outline src/core' (list symbols), 'peek-def FnName' (show definition), 'find-references Name' (find usages).",
      parameters: {
        type: "object",
        properties: {
          subcommand: { type: "string", description: "e.g. 'outline src/core', 'peek-def ApiState::search', 'find-references parse_kv_fields'" },
        },
        required: ["subcommand"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "diff",
      description: "Show git diff of current changes.",
      parameters: { type: "object", properties: {}, required: [] },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "done",
      description: "Signal task completion. Call ONLY after moon check and moon test both pass.",
      parameters: {
        type: "object",
        properties: {
          summary: { type: "string", description: "What was done" },
        },
        required: ["summary"],
      },
    },
  },
];

// ---- Tool execution ----

function shell(cmd: string, timeout = 60_000): string {
  try {
    return execSync(cmd, {
      cwd: REPO_ROOT,
      timeout,
      encoding: "utf-8",
      maxBuffer: 2 * 1024 * 1024,
      env: { ...process.env, FORCE_COLOR: "0" },
    }).slice(-6000);
  } catch (err: unknown) {
    const e = err as { stdout?: string; stderr?: string; status?: number };
    return `Exit ${e.status}:\n${((e.stdout || "") + "\n" + (e.stderr || "")).slice(-6000)}`;
  }
}

function executeTool(name: string, args: Record<string, unknown>): string {
  try {
    switch (name) {
      case "read_file": {
        const filePath = path.resolve(REPO_ROOT, args.path as string);
        if (!fs.existsSync(filePath)) return `Error: not found: ${args.path}`;
        const lines = fs.readFileSync(filePath, "utf-8").split("\n");
        const s = (args.start_line as number) || 1;
        const e = (args.end_line as number) || lines.length;
        const selected = lines.slice(s - 1, e);
        const result = selected.map((l, i) => `${s + i}| ${l}`).join("\n");
        return (result.length > 12000 ? result.slice(0, 12000) + "\n..." : result) +
          `\n(${lines.length} total lines)`;
      }
      case "write_file": {
        const filePath = path.resolve(REPO_ROOT, args.path as string);
        fs.mkdirSync(path.dirname(filePath), { recursive: true });
        fs.writeFileSync(filePath, args.content as string, "utf-8");
        return `Written ${(args.content as string).length} chars to ${args.path}`;
      }
      case "patch_file": {
        const filePath = path.resolve(REPO_ROOT, args.path as string);
        if (!fs.existsSync(filePath)) return `Error: not found: ${args.path}`;
        const lines = fs.readFileSync(filePath, "utf-8").split("\n");
        const s = (args.start_line as number) || 1;
        const e = (args.end_line as number) || s;
        const newContent = args.content as string;
        const replacement = newContent.length > 0 ? newContent.split("\n") : [];
        const result = [...lines.slice(0, s - 1), ...replacement, ...lines.slice(e)];
        fs.writeFileSync(filePath, result.join("\n"), "utf-8");
        return `Patched ${args.path}: lines ${s}-${e} → ${replacement.length} lines. Now ${result.length} lines.`;
      }
      case "list_dir": {
        const dirPath = path.resolve(REPO_ROOT, (args.path as string) || ".");
        if (!fs.existsSync(dirPath)) return `Error: not found: ${args.path}`;
        return fs.readdirSync(dirPath, { withFileTypes: true })
          .filter(e => !e.name.startsWith(".") && !["node_modules", "_build", ".mooncakes"].includes(e.name))
          .map(e => `${e.isDirectory() ? "[dir]" : "[file]"} ${e.name}`)
          .join("\n");
      }
      case "run": {
        if (/rm\s+-rf|rmdir/i.test(args.command as string)) return "Error: blocked";
        return shell(args.command as string);
      }
      case "search": {
        const q = args.query as string;
        const g = (args.glob as string) || "";
        const gArg = g ? `--include='${g}'` : "";
        return shell(
          `grep -rn ${gArg} --exclude-dir={node_modules,_build,.mooncakes,.git,.bithub,.wrangler,test-results} ${JSON.stringify(q)} src/ e2e/ 2>/dev/null | head -30`,
          10_000,
        ) || "No matches";
      }
      case "moon_ide": {
        return shell(`moon ide ${args.subcommand}`, 15_000);
      }
      case "diff": {
        const staged = shell("git diff --stat");
        const untracked = shell("git status --short 2>/dev/null | head -10");
        return staged + "\n" + untracked;
      }
      case "done":
        return `DONE: ${args.summary}`;
      default:
        return `Unknown tool: ${name}`;
    }
  } catch (err: unknown) {
    return `Error: ${(err as Error).message}`;
  }
}

// ---- LLM ----

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

async function llmStep(messages: Message[]): Promise<{
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
    choices?: Array<{ message?: Message }>;
    error?: { message?: string };
  };
  if (data.error) throw new Error(`LLM: ${data.error.message}`);
  const msg = data.choices?.[0]?.message;
  if (!msg) throw new Error("No response");

  if (msg.tool_calls?.length) {
    messages.push(msg);
    let isDone = false;
    let summary = "";

    for (const call of msg.tool_calls) {
      let args: Record<string, unknown>;
      try {
        args = JSON.parse(call.function.arguments);
      } catch {
        messages.push({ role: "tool", content: "JSON parse error. Simplify your arguments.", tool_call_id: call.id });
        continue;
      }

      const argPreview = JSON.stringify(args).slice(0, 80);
      console.log(`  → ${call.function.name}(${argPreview})`);

      const result = executeTool(call.function.name, args);
      const preview = result.slice(0, 120).replace(/\n/g, " ");
      console.log(`    ${preview}${result.length > 120 ? "..." : ""}`);

      messages.push({ role: "tool", content: result, tool_call_id: call.id });

      if (call.function.name === "done") {
        isDone = true;
        summary = args.summary as string;
      }
    }
    return { done: isDone, summary };
  }

  // Text response (no tool calls)
  messages.push(msg);
  console.log(`  Agent: ${(msg.content || "").slice(0, 200)}`);
  return { done: true, summary: msg.content || "" };
}

// ---- System prompt ----

const SYSTEM_PROMPT = `You are ${AGENT_NAME}, a coding agent for bithub (GitHub-like platform in MoonBit).

## Workflow (act fast, minimize exploration)
1. Read the task — go DIRECTLY to mentioned files
2. Use search or moon_ide to find exact locations
3. Edit with patch_file (existing files) or write_file (new files)
4. Run "moon check --target js" — if errors, read them and fix
5. Run "moon test --target js" — if failures, fix
6. Run diff() to review changes
7. Call done()

## MoonBit Rules
- Blocks separated by \`///|\`
- \`fn\` = private, \`pub fn\` = public
- Type params: \`fn[T] name(val: T)\` not \`fn name[T](val: T)\`
- Errors: \`fn f() -> Int raise Error\` not \`-> Int!Error\`
- No \`return\` needed, no \`++\`/\`--\`, no \`await\`
- Range loops: \`for i in 0..<n { }\`
- Methods: \`pub fn Type::method(self : Type)\`
- String interpolation: \`"\\{name}"\`
- Snapshot tests: \`inspect(val, content="...")\`

## Testing (IMPORTANT)
- Black-box tests (*_test.mbt): can ONLY call pub functions via package name
- White-box tests (*_wbtest.mbt): can call PRIVATE functions directly
- For testing private functions, create a _wbtest.mbt file, NOT _test.mbt
- Do NOT change fn to pub fn just for testing

## Tools
- patch_file: edit specific lines (preferred for existing files)
- write_file: create new files only
- moon_ide: "outline src/core" / "peek-def FnName" / "find-references Name"
- search: grep source code
- diff: show current changes before calling done

## File Structure
- src/core/*.mbt — data layer (Storage, ApiState, CI, Issues, PRs)
- src/core/seed.mbt — demo seed data
- src/adapters/mars_http/ — HTTP routing + SSR rendering
- e2e/*.spec.ts — Playwright E2E tests`;

// ---- Main ----

async function main() {
  console.log(`=== Agent Harness v2 ===`);
  console.log(`Model: ${MODEL} | Agent: ${AGENT_NAME} | Max: ${MAX_TURNS} turns\n`);

  // Get task
  let taskDescription: string;
  if (ISSUE_ID) {
    const html = await (await fetch(`${BITHUB_URL}/issues/${ISSUE_ID}`)).text();
    const titleMatch = html.match(/<h1[^>]*>(.*?)<\/h1>/s);
    const title = titleMatch ? titleMatch[1].replace(/<[^>]*>/g, "").trim() : "";
    const bodyMatch = html.match(/aria-label="issue body"[^>]*>([\s\S]*?)(?=<h2|<footer)/);
    const body = bodyMatch ? bodyMatch[1].replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim() : "";
    taskDescription = `Issue #${ISSUE_ID}: ${title}\n\n${body}`.slice(0, 1500);
    console.log(`Task: Issue #${ISSUE_ID} — ${title}\n`);
  } else if (TASK) {
    taskDescription = TASK;
    console.log(`Task: ${TASK.slice(0, 100)}\n`);
  } else {
    console.error("Set ISSUE_ID or TASK");
    process.exit(1);
  }

  // Git safety: stash any existing changes
  shell("git stash --include-untracked -m 'agent-harness-backup' 2>/dev/null");

  const messages: Message[] = [
    { role: "system", content: SYSTEM_PROMPT },
    { role: "user", content: taskDescription },
  ];

  let succeeded = false;
  for (let turn = 0; turn < MAX_TURNS; turn++) {
    console.log(`\n--- Turn ${turn + 1}/${MAX_TURNS} ---`);
    try {
      const { done, summary } = await llmStep(messages);
      if (done) {
        console.log(`\n=== Done: ${summary.slice(0, 200)} ===`);
        succeeded = true;
        break;
      }
    } catch (err) {
      console.error(`Turn error: ${(err as Error).message}`);
      // Feed error back to LLM
      messages.push({ role: "user", content: `Error occurred: ${(err as Error).message}. Please continue.` });
    }
  }

  // Validate final state
  console.log("\n--- Final validation ---");
  const checkResult = shell("moon check --target js 2>&1");
  const hasErrors = /\d+ errors/.test(checkResult) && !checkResult.includes("0 errors");
  console.log(`moon check: ${hasErrors ? "FAILED" : "OK"}`);

  if (!hasErrors) {
    const testResult = shell("moon test --target js 2>&1");
    const testMatch = testResult.match(/Total tests: (\d+), passed: (\d+), failed: (\d+)/);
    if (testMatch) {
      console.log(`moon test: ${testMatch[2]}/${testMatch[1]} passed, ${testMatch[3]} failed`);
      if (testMatch[3] !== "0") succeeded = false;
    }
  } else {
    succeeded = false;
  }

  if (!succeeded) {
    console.log("\nRolling back changes...");
    shell("git checkout -- . 2>/dev/null");
    shell("git clean -fd src/ 2>/dev/null");
    shell("git stash pop 2>/dev/null");
    console.log("Rolled back.");
  } else {
    // Restore stashed changes on top
    shell("git stash pop 2>/dev/null");
    console.log("\nChanges:");
    console.log(shell("git diff --stat"));
    console.log(shell("git status --short | grep '??' | head -5"));
  }
}

main().catch((err) => {
  console.error("Agent failed:", err);
  shell("git checkout -- . 2>/dev/null");
  shell("git clean -fd src/ 2>/dev/null");
  shell("git stash pop 2>/dev/null");
  process.exit(1);
});
