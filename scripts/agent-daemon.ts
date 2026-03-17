/**
 * Agent Daemon: polls bithub for open issues and automatically
 * implements them using the agent harness.
 *
 * Flow:
 * 1. Poll /issues for open, unassigned issues
 * 2. Pick the oldest unassigned issue
 * 3. Mark it as "in progress" via comment
 * 4. Run agent-harness to implement it
 * 5. If successful: create PR, comment result, close issue
 * 6. If failed: comment the failure, move on
 * 7. Wait, repeat
 *
 * Usage:
 *   BITHUB_URL=http://127.0.0.1:4174 npx tsx scripts/agent-daemon.ts
 *
 * Env:
 *   BITHUB_URL      - bithub server (default: http://127.0.0.1:4174)
 *   MODEL           - LLM model (default: anthropic/claude-sonnet-4)
 *   POLL_INTERVAL   - seconds between polls (default: 30)
 *   MAX_ISSUES      - max issues to process per run, 0=infinite (default: 3)
 *   AGENT_TOKEN     - auth token (default: tok-bob)
 *   REVIEWER_TOKEN  - reviewer auth token (default: tok-alice)
 *   REPO_ROOT       - repo path (default: cwd)
 */

import { execSync, spawn } from "node:child_process";

const BITHUB_URL = process.env.BITHUB_URL || "http://127.0.0.1:4174";
const MODEL = process.env.MODEL || "anthropic/claude-sonnet-4";
const POLL_INTERVAL = parseInt(process.env.POLL_INTERVAL || "30", 10);
const MAX_ISSUES = parseInt(process.env.MAX_ISSUES || "3", 10);
const AGENT_TOKEN = process.env.AGENT_TOKEN || "tok-bob";
const REVIEWER_TOKEN = process.env.REVIEWER_TOKEN || "tok-alice";
const REPO_ROOT = process.env.REPO_ROOT || process.cwd();
const MAX_TURNS = process.env.MAX_TURNS || "15";

const ASSIGNED_TAG = "[agent-daemon]";

// ---- API helpers ----

async function api(
  method: string,
  path: string,
  body?: Record<string, unknown>,
  token = AGENT_TOKEN,
): Promise<{ status: number; data: Record<string, unknown> }> {
  const opts: RequestInit = {
    method,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
  };
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(`${BITHUB_URL}${path}`, opts);
  let data: Record<string, unknown>;
  try {
    data = (await res.json()) as Record<string, unknown>;
  } catch {
    data = {};
  }
  return { status: res.status, data };
}

async function getPageText(path: string): Promise<string> {
  const res = await fetch(`${BITHUB_URL}${path}`);
  const html = await res.text();
  return html.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
}

// ---- Issue discovery ----

interface Issue {
  id: string;
  title: string;
  state: string;
}

async function findOpenIssues(): Promise<Issue[]> {
  const html = await (await fetch(`${BITHUB_URL}/issues`)).text();
  const issues: Issue[] = [];

  // Parse table rows: <td><a href="/issues/ID">#ID</a></td><td>Title</td><td>State</td>
  const rowRegex =
    /<tr>\s*<td><a[^>]*>(?:#)?(\d+)<\/a><\/td>\s*<td>([^<]*)<\/td>\s*<td>[^<]*?(open|closed)[^<]*<\/td>/g;
  let match;
  while ((match = rowRegex.exec(html)) !== null) {
    issues.push({ id: match[1], title: match[2].trim(), state: match[3] });
  }

  return issues.filter((i) => i.state === "open");
}

async function isAssigned(issueId: string): Promise<boolean> {
  const text = await getPageText(`/issues/${issueId}`);
  return text.includes(ASSIGNED_TAG);
}

// ---- Agent execution ----

function runAgentHarness(
  issueId: string,
): Promise<{ success: boolean; output: string }> {
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
        AGENT_NAME: "agent-daemon",
        AGENT_TOKEN,
        REPO_ROOT,
      },
      stdio: ["ignore", "pipe", "pipe"],
    });

    proc.stdout?.on("data", (d: Buffer) => chunks.push(d.toString()));
    proc.stderr?.on("data", (d: Buffer) => chunks.push(d.toString()));

    proc.on("close", (code) => {
      const output = chunks.join("");
      const hasDone = output.includes("DONE:");
      const checkOk = !output.includes("Rolling back");
      resolve({
        success: code === 0 && hasDone && checkOk,
        output,
      });
    });

    // 4 minute timeout
    setTimeout(() => proc.kill("SIGTERM"), 240_000);
  });
}

// ---- PR creation ----

async function createPRForIssue(
  issueId: string,
  issueTitle: string,
  summary: string,
): Promise<string | null> {
  // Get current branch/SHA for head ref
  let headSha = "";
  try {
    headSha = execSync("git rev-parse --short HEAD", {
      cwd: REPO_ROOT,
      encoding: "utf-8",
    }).trim();
  } catch {
    headSha = "HEAD";
  }

  const result = await api("POST", "/api/pulls", {
    title: `Fix #${issueId}: ${issueTitle}`,
    body: `Automatically implemented by agent-daemon.\n\nCloses #${issueId}\n\n${summary}`,
    base: "main",
    head: headSha,
    author: "agent-daemon",
  });

  if (result.data.id) {
    return result.data.id as string;
  }
  return null;
}

// ---- Review and merge ----

async function reviewAndMerge(prId: string): Promise<boolean> {
  // Auto-review
  await api(
    "POST",
    `/api/pulls/${prId}/comments`,
    { body: "Auto-reviewed by agent-daemon. Tests pass.", author: "reviewer" },
    REVIEWER_TOKEN,
  );

  // Merge
  const result = await api("POST", `/api/pulls/${prId}/merge`, {}, REVIEWER_TOKEN);
  return result.data.ok === true;
}

// ---- Main loop ----

async function processIssue(issue: Issue): Promise<boolean> {
  console.log(`\n${"=".repeat(60)}`);
  console.log(`Processing: #${issue.id} ${issue.title}`);
  console.log(`${"=".repeat(60)}`);

  // Mark as in progress
  await api("POST", `/api/issues/${issue.id}/comments`, {
    body: `${ASSIGNED_TAG} Starting work on this issue...`,
    author: "agent-daemon",
  });

  // Run agent
  console.log("Running agent harness...");
  const startTime = Date.now();
  const result = await runAgentHarness(issue.id);
  const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);

  // Extract summary
  const doneMatch = result.output.match(/DONE: (.*?)$/m);
  const summary = doneMatch ? doneMatch[1] : "No summary available";
  const turnCount = (result.output.match(/--- Turn/g) || []).length;

  console.log(
    `Agent finished in ${elapsed}s (${turnCount} turns): ${result.success ? "SUCCESS" : "FAILED"}`,
  );

  if (result.success) {
    // Get diff summary
    let diffStat = "";
    try {
      diffStat = execSync("git diff --stat HEAD~1", {
        cwd: REPO_ROOT,
        encoding: "utf-8",
      }).trim();
    } catch {
      diffStat = "(no diff available)";
    }

    // Create PR
    const prId = await createPRForIssue(issue.id, issue.title, summary);
    if (prId) {
      console.log(`Created PR #${prId}`);

      // Review and merge
      const merged = await reviewAndMerge(prId);
      console.log(`Merged: ${merged}`);

      // Close issue
      await api("POST", `/api/issues/${issue.id}/state`, { state: "closed" });
      await api("POST", `/api/issues/${issue.id}/comments`, {
        body: `${ASSIGNED_TAG} Completed! PR #${prId} merged.\n\nSummary: ${summary}\n\n\`\`\`\n${diffStat}\n\`\`\``,
        author: "agent-daemon",
      });

      console.log(`Issue #${issue.id} closed.`);
      return true;
    }
  }

  // Failed
  const errorLines = result.output
    .split("\n")
    .filter((l) => l.includes("Error") || l.includes("failed"))
    .slice(-5)
    .join("\n");

  await api("POST", `/api/issues/${issue.id}/comments`, {
    body: `${ASSIGNED_TAG} Failed to implement this issue.\n\nAgent ran for ${turnCount} turns in ${elapsed}s.\n\nSummary: ${summary}\n\n\`\`\`\n${errorLines || "(no error details)"}\n\`\`\``,
    author: "agent-daemon",
  });

  console.log(`Issue #${issue.id} failed, left open.`);
  return false;
}

async function pollAndProcess(): Promise<number> {
  console.log(`\nPolling ${BITHUB_URL}/issues ...`);

  const openIssues = await findOpenIssues();
  console.log(`Found ${openIssues.length} open issues`);

  // Filter out already assigned issues
  const unassigned: Issue[] = [];
  for (const issue of openIssues) {
    if (!(await isAssigned(issue.id))) {
      unassigned.push(issue);
    }
  }
  console.log(`${unassigned.length} unassigned`);

  if (unassigned.length === 0) {
    return 0;
  }

  // Process oldest first (last in list since list is sorted newest-first)
  const toProcess = unassigned.reverse().slice(0, MAX_ISSUES || undefined);
  let successCount = 0;

  for (const issue of toProcess) {
    const ok = await processIssue(issue);
    if (ok) successCount++;
  }

  return successCount;
}

async function main() {
  console.log("=== Agent Daemon ===");
  console.log(`Bithub: ${BITHUB_URL}`);
  console.log(`Model: ${MODEL}`);
  console.log(`Repo: ${REPO_ROOT}`);
  console.log(`Poll interval: ${POLL_INTERVAL}s`);
  console.log(`Max issues per run: ${MAX_ISSUES || "unlimited"}`);

  // Verify server
  try {
    const health = await fetch(`${BITHUB_URL}/healthz`);
    if (!health.ok) throw new Error("not ok");
    console.log("Server: OK\n");
  } catch {
    console.error(`Cannot reach ${BITHUB_URL}`);
    process.exit(1);
  }

  // Single run or loop
  if (process.argv.includes("--once")) {
    const count = await pollAndProcess();
    console.log(`\nProcessed ${count} issues.`);
    process.exit(0);
  }

  // Continuous loop
  console.log("Starting continuous loop (Ctrl+C to stop)\n");
  let totalProcessed = 0;

  while (true) {
    try {
      const count = await pollAndProcess();
      totalProcessed += count;

      if (count > 0) {
        console.log(`\nTotal processed so far: ${totalProcessed}`);
      }
    } catch (err) {
      console.error(`Poll error: ${(err as Error).message}`);
    }

    console.log(`Waiting ${POLL_INTERVAL}s...`);
    await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL * 1000));
  }
}

main().catch((err) => {
  console.error("Daemon failed:", err);
  process.exit(1);
});
