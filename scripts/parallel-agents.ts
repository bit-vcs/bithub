/**
 * Parallel agent runner: spawns multiple agents on different tasks simultaneously.
 *
 * Creates issues, runs agents in parallel, validates combined result.
 *
 * Usage:
 *   BITHUB_URL=http://127.0.0.1:4174 npx tsx scripts/parallel-agents.ts
 */

import { execSync, spawn, type ChildProcess } from "node:child_process";

const BITHUB_URL = process.env.BITHUB_URL || "http://127.0.0.1:4174";
const MODEL = process.env.MODEL || "anthropic/claude-sonnet-4";
const MAX_TURNS = process.env.MAX_TURNS || "12";
const REPO_ROOT = process.cwd();

// ---- Task definitions ----
// Each task targets a DIFFERENT file to minimize conflicts

const TASKS: Array<{
  title: string;
  body: string;
  agent: string;
  token: string;
}> = [
  {
    title: "Add unit tests for simple_hash in api_state.mbt",
    body: `The simple_hash function (around line 1310 in src/core/api_state.mbt) generates hash values but has no tests.

Steps:
1. search for "fn simple_hash" to find exact location
2. patch_file to change "fn simple_hash" to "pub fn simple_hash"
3. Create NEW file src/core/hash_test.mbt with tests:
   - simple_hash("") returns a number
   - simple_hash("hello") returns consistent value
   - simple_hash("a") != simple_hash("b")
   - same input gives same output
4. moon check --target js
5. moon test --target js`,
    agent: "agent-alpha",
    token: "tok-bob",
  },
  {
    title: "Add unit tests for xml_escape in api_state.mbt",
    body: `The xml_escape function (around line 1532 in src/core/api_state.mbt) escapes XML special chars but has no tests.

Steps:
1. search for "fn xml_escape" to find exact location
2. patch_file to change "fn xml_escape" to "pub fn xml_escape" if not already pub
3. Create NEW file src/core/xml_test.mbt with tests:
   - xml_escape("") returns ""
   - xml_escape("hello") returns "hello"
   - xml_escape("&") returns "&amp;"
   - xml_escape("<>") returns "&lt;&gt;"
   - xml_escape("a & b") returns "a &amp; b"
4. moon check --target js
5. moon test --target js`,
    agent: "agent-beta",
    token: "tok-bob",
  },
  {
    title: "Fix deprecated fn syntax in fs_storage.mbt",
    body: `Line 18 in src/core/fs_storage.mbt uses deprecated method syntax:
fn fs_key_path(self : FsStorage, key : String) -> String

Change to:
fn FsStorage::fs_key_path(self : FsStorage, key : String) -> String

Steps:
1. read_file("src/core/fs_storage.mbt", start_line=16, end_line=20)
2. patch_file to replace line 18 with the new syntax
3. moon check --target js
4. moon test --target js`,
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

function runAgent(
  issueId: string,
  agentName: string,
  token: string,
): Promise<{ agent: string; issueId: string; exitCode: number; output: string }> {
  return new Promise((resolve) => {
    const chunks: string[] = [];
    const proc = spawn(
      "npx",
      ["tsx", "scripts/agent-harness.ts"],
      {
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
      },
    );

    proc.stdout?.on("data", (d: Buffer) => chunks.push(d.toString()));
    proc.stderr?.on("data", (d: Buffer) => chunks.push(d.toString()));

    proc.on("close", (code) => {
      resolve({
        agent: agentName,
        issueId,
        exitCode: code || 0,
        output: chunks.join(""),
      });
    });

    // Timeout after 3 minutes
    setTimeout(() => {
      proc.kill("SIGTERM");
    }, 180_000);
  });
}

// ---- Main ----

async function main() {
  console.log("=== Parallel Agent Runner ===");
  console.log(`Model: ${MODEL}`);
  console.log(`Tasks: ${TASKS.length}`);
  console.log(`Bithub: ${BITHUB_URL}`);
  console.log("");

  // Verify server
  const health = await fetch(`${BITHUB_URL}/healthz`);
  if (!health.ok) {
    console.error("Server not running");
    process.exit(1);
  }

  // Phase 1: Create issues
  console.log("--- Creating issues ---");
  const issueIds: string[] = [];
  for (const task of TASKS) {
    const result = await bithubPost(
      "/api/issues",
      { title: task.title, body: task.body, author: task.agent },
      task.token,
    );
    issueIds.push(result.id as string);
    console.log(`  Issue #${result.id}: ${task.title.slice(0, 50)}... (${task.agent})`);
  }

  // Phase 2: Run agents in parallel
  console.log("\n--- Launching agents in parallel ---");
  const startTime = Date.now();

  const promises = TASKS.map((task, i) =>
    runAgent(issueIds[i], task.agent, task.token),
  );

  const results = await Promise.all(promises);

  const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
  console.log(`\n--- All agents finished in ${elapsed}s ---\n`);

  // Phase 3: Report individual results
  for (const r of results) {
    const lastLines = r.output.split("\n").slice(-5).join("\n");
    const turnCount = (r.output.match(/--- Turn/g) || []).length;
    const hasDone = r.output.includes("DONE:");
    const status = r.exitCode === 0 && hasDone ? "✓" : r.exitCode === 0 ? "⚠" : "✗";
    console.log(`${status} ${r.agent} (Issue #${r.issueId}): ${turnCount} turns, exit ${r.exitCode}`);
    if (hasDone) {
      const doneMatch = r.output.match(/DONE: (.*?)$/m);
      if (doneMatch) console.log(`  Summary: ${doneMatch[1].slice(0, 120)}`);
    }
    if (r.exitCode !== 0) {
      console.log(`  Last output: ${lastLines.slice(0, 200)}`);
    }
  }

  // Phase 4: Validate combined result
  console.log("\n--- Validating combined result ---");
  try {
    const checkOutput = execSync("moon check --target js 2>&1", {
      cwd: REPO_ROOT,
      encoding: "utf-8",
      timeout: 60_000,
    });
    const hasErrors = checkOutput.includes("errors");
    console.log(`moon check: ${hasErrors ? "FAILED" : "OK"}`);
    if (hasErrors) {
      const errorLines = checkOutput.split("\n").filter(l => l.includes("Error"));
      console.log(`  ${errorLines.slice(0, 5).join("\n  ")}`);
    }
  } catch (err) {
    const e = err as { stdout?: string; stderr?: string };
    console.log("moon check: FAILED");
    const out = ((e.stdout || "") + (e.stderr || "")).split("\n").filter(l => l.includes("Error"));
    console.log(`  ${out.slice(0, 5).join("\n  ")}`);
  }

  try {
    const testOutput = execSync("moon test --target js 2>&1", {
      cwd: REPO_ROOT,
      encoding: "utf-8",
      timeout: 120_000,
    });
    const totalMatch = testOutput.match(/Total tests: (\d+), passed: (\d+)/);
    if (totalMatch) {
      console.log(`moon test: ${totalMatch[2]}/${totalMatch[1]} passed`);
    }
  } catch (err) {
    const e = err as { stdout?: string };
    const totalMatch = (e.stdout || "").match(/Total tests: (\d+), passed: (\d+), failed: (\d+)/);
    if (totalMatch) {
      console.log(`moon test: ${totalMatch[2]}/${totalMatch[1]} passed, ${totalMatch[3]} failed`);
    } else {
      console.log("moon test: FAILED");
    }
  }

  // Phase 5: Show file changes
  console.log("\n--- File changes ---");
  try {
    const status = execSync("git diff --stat && git status --short | grep '??' | head -10", {
      cwd: REPO_ROOT,
      encoding: "utf-8",
    });
    console.log(status);
  } catch {
    console.log("(no changes)");
  }

  console.log("\n=== Done ===");
}

main().catch((err) => {
  console.error("Runner failed:", err);
  process.exit(1);
});
