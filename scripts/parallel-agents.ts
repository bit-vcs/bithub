/**
 * Parallel agent runner v2.
 *
 * Spawns agents on meaningful refactoring/improvement tasks.
 * Each task targets different files to avoid conflicts.
 * Validates combined result with moon check + test.
 * Rolls back on failure.
 *
 * Usage:
 *   BITHUB_URL=http://127.0.0.1:4174 npx tsx scripts/parallel-agents.ts
 */

import { execSync, spawn } from "node:child_process";

const BITHUB_URL = process.env.BITHUB_URL || "http://127.0.0.1:4174";
const MODEL = process.env.MODEL || "anthropic/claude-sonnet-4";
const MAX_TURNS = process.env.MAX_TURNS || "15";
const REPO_ROOT = process.cwd();

// ---- Meaningful tasks targeting different files ----

const TASKS: Array<{
  title: string;
  body: string;
  agent: string;
  token: string;
}> = [
  {
    title: "Add whitebox tests for string_contains in api_state",
    body: `The string_contains function (private, in src/core/api_state.mbt around line 900) is used for code search. It needs whitebox tests.

Create src/core/search_wbtest.mbt (whitebox test file — can access private functions).
Test cases:
- Empty needle matches any string
- Exact match
- Substring at start, middle, end
- No match
- Case sensitivity (should be case-sensitive)
- Needle longer than haystack returns false

Use inspect() for verifiable assertions. Run moon check + moon test.`,
    agent: "agent-alpha",
    token: "tok-bob",
  },
  {
    title: "Add whitebox tests for count_files in api_state",
    body: `The count_files function (private, in src/core/api_state.mbt) recursively counts files in Storage. It needs whitebox tests.

Create src/core/stats_wbtest.mbt (whitebox test — can access private functions).
Steps:
1. search for "fn count_files" to find the exact signature
2. Create tests using MapStorage:
   - Empty storage returns 0
   - Single file returns 1
   - Files in subdirectories are counted
   - Directories themselves are not counted
3. moon check + moon test`,
    agent: "agent-beta",
    token: "tok-bob",
  },
  {
    title: "Fix deprecated f!() syntax in ci.mbt",
    body: `Line 486 in src/core/ci.mbt has deprecated syntax:
    @strconv.parse_int!(idx_str)
should be:
    @strconv.parse_int(idx_str)

(The ! suffix is no longer needed for error-raising calls.)

Steps:
1. read_file("src/core/ci.mbt", start_line=484, end_line=490)
2. patch_file to remove the ! from parse_int!
3. moon check --target js to verify
4. moon test --target js to verify`,
    agent: "agent-gamma",
    token: "tok-bob",
  },
];

// ---- Helpers ----

async function bithubPost(
  path: string,
  data: Record<string, unknown>,
  token: string,
): Promise<Record<string, unknown>> {
  const res = await fetch(`${BITHUB_URL}${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(data),
  });
  return (await res.json()) as Record<string, unknown>;
}

function shell(cmd: string): string {
  try {
    return execSync(cmd, { cwd: REPO_ROOT, timeout: 120_000, encoding: "utf-8" });
  } catch (err: unknown) {
    const e = err as { stdout?: string; stderr?: string };
    return (e.stdout || "") + "\n" + (e.stderr || "");
  }
}

function runAgent(
  issueId: string,
  agentName: string,
  token: string,
): Promise<{ agent: string; issueId: string; exitCode: number; output: string }> {
  return new Promise((resolve) => {
    const chunks: string[] = [];
    const proc = spawn("npx", ["tsx", "scripts/agent-harness.ts"], {
      cwd: REPO_ROOT,
      env: {
        ...process.env,
        BITHUB_URL,
        ISSUE_ID: issueId,
        MODEL,
        MAX_TURNS,
        AGENT_NAME: agentName,
        AGENT_TOKEN: token,
        REPO_ROOT,
      },
      stdio: ["ignore", "pipe", "pipe"],
    });

    proc.stdout?.on("data", (d: Buffer) => chunks.push(d.toString()));
    proc.stderr?.on("data", (d: Buffer) => chunks.push(d.toString()));
    proc.on("close", (code) => {
      resolve({ agent: agentName, issueId, exitCode: code || 0, output: chunks.join("") });
    });

    setTimeout(() => proc.kill("SIGTERM"), 180_000);
  });
}

// ---- Main ----

async function main() {
  console.log("=== Parallel Agent Runner v2 ===");
  console.log(`Model: ${MODEL} | Tasks: ${TASKS.length}\n`);

  // Verify
  const health = await fetch(`${BITHUB_URL}/healthz`);
  if (!health.ok) { console.error("Server not running"); process.exit(1); }

  // Save clean state
  shell("git stash --include-untracked -m 'parallel-backup' 2>/dev/null");

  // Create issues
  console.log("--- Creating issues ---");
  const issueIds: string[] = [];
  for (const task of TASKS) {
    const r = await bithubPost("/api/issues", { title: task.title, body: task.body, author: task.agent }, task.token);
    issueIds.push(r.id as string);
    console.log(`  #${r.id} ${task.title.slice(0, 60)} → ${task.agent}`);
  }

  // Launch parallel
  console.log("\n--- Launching agents ---");
  const t0 = Date.now();
  const results = await Promise.all(
    TASKS.map((task, i) => runAgent(issueIds[i], task.agent, task.token)),
  );
  const elapsed = ((Date.now() - t0) / 1000).toFixed(1);
  console.log(`\n--- All finished in ${elapsed}s ---\n`);

  // Report
  for (const r of results) {
    const turns = (r.output.match(/--- Turn/g) || []).length;
    const hasDone = r.output.includes("DONE:");
    const hasRollback = r.output.includes("Rolling back");
    const icon = hasDone ? "✓" : hasRollback ? "✗" : "⚠";
    console.log(`${icon} ${r.agent} (#${r.issueId}): ${turns} turns`);
    if (hasDone) {
      const m = r.output.match(/DONE: (.*?)$/m);
      if (m) console.log(`  ${m[1].slice(0, 120)}`);
    }
  }

  // Validate
  console.log("\n--- Combined validation ---");
  const checkOut = shell("moon check --target js 2>&1");
  const checkOk = checkOut.includes("0 errors");
  console.log(`moon check: ${checkOk ? "OK" : "FAILED"}`);

  if (!checkOk) {
    const errs = checkOut.split("\n").filter(l => l.includes("Error:")).slice(0, 5);
    errs.forEach(e => console.log(`  ${e}`));
  }

  const testOut = shell("moon test --target js 2>&1");
  const testMatch = testOut.match(/Total tests: (\d+), passed: (\d+), failed: (\d+)/);
  if (testMatch) {
    console.log(`moon test: ${testMatch[2]}/${testMatch[1]} passed, ${testMatch[3]} failed`);
  }

  // Show changes
  console.log("\n--- Changes ---");
  console.log(shell("git diff --stat"));
  const untracked = shell("git status --short 2>/dev/null").split("\n").filter(l => l.startsWith("??"));
  if (untracked.length) console.log(untracked.join("\n"));

  const allGood = checkOk && testMatch && testMatch[3] === "0";
  if (!allGood) {
    console.log("\n⚠ Validation failed — rolling back");
    shell("git checkout -- . 2>/dev/null");
    shell("git clean -fd src/ e2e/ 2>/dev/null");
  }
  shell("git stash pop 2>/dev/null");

  console.log(`\n=== ${allGood ? "SUCCESS" : "ROLLED BACK"} ===`);
}

main().catch((err) => {
  console.error("Failed:", err);
  shell("git checkout -- . 2>/dev/null && git clean -fd src/ 2>/dev/null && git stash pop 2>/dev/null");
  process.exit(1);
});
