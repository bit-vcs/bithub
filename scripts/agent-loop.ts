/**
 * Autonomous improvement loop:
 * 1. Analyst agent reads the codebase and creates improvement issues
 * 2. Developer agent picks up issues and implements them
 *
 * Usage:
 *   BITHUB_URL=http://127.0.0.1:4174 npx tsx scripts/agent-loop.ts
 */

const BITHUB_URL = process.env.BITHUB_URL || "http://127.0.0.1:4174";
const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY!;
const MODEL = process.env.MODEL || "anthropic/claude-sonnet-4";

const ANALYST_TOKEN = "tok-alice";
const DEV_TOKEN = "tok-bob";

// ---- LLM ----

interface Msg { role: "system" | "user" | "assistant"; content: string }

async function llm(messages: Msg[], maxTokens = 2048): Promise<string> {
  const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENROUTER_API_KEY}`,
    },
    body: JSON.stringify({ model: MODEL, messages, max_tokens: maxTokens, temperature: 0.3 }),
  });
  const data = (await res.json()) as {
    choices?: { message?: { content?: string } }[];
    error?: { message?: string };
  };
  if (data.error) throw new Error(`LLM: ${data.error.message}`);
  return data.choices?.[0]?.message?.content || "";
}

// ---- Bithub API ----

async function post(path: string, data: Record<string, unknown>, token: string) {
  const res = await fetch(`${BITHUB_URL}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify(data),
  });
  return (await res.json()) as Record<string, unknown>;
}

async function getText(path: string): Promise<string> {
  const html = await (await fetch(`${BITHUB_URL}${path}`)).text();
  return html.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
}

async function getFile(path: string): Promise<string | null> {
  const text = await getText(`/file?path=${encodeURIComponent(path)}`);
  // Check if it's a 404
  if (text.includes("not found")) return null;
  // Strip layout chrome - extract main content
  return text;
}

async function searchCode(query: string): Promise<string> {
  return getText(`/search?q=${encodeURIComponent(query)}`);
}

// ---- Phase 1: Analyst ----

async function analyzeAndCreateIssues(): Promise<string[]> {
  console.log("\n========================================");
  console.log("Phase 1: Analyst reads codebase");
  console.log("========================================\n");

  // Read key files to understand the project
  const readme = await getFile("README.md") || "";
  const serverPreview = await getFile("src/adapters/mars_http/server.mbt") || "";
  const apiStatePreview = await getFile("src/core/api_state.mbt") || "";
  const searchResults = await searchCode("fn render_");

  const codeContext = `
README (preview): ${readme.slice(0, 500)}

server.mbt (preview): ${serverPreview.slice(0, 800)}

api_state.mbt (preview): ${apiStatePreview.slice(0, 800)}

Search "fn render_" results: ${searchResults.slice(0, 600)}
`.trim();

  console.log("Read codebase context (" + codeContext.length + " chars)");

  // Ask LLM to suggest improvements
  const analysis = await llm([
    {
      role: "system",
      content: `You are a senior code analyst reviewing the bithub project (a GitHub-like platform built in MoonBit).

Suggest exactly 2 concrete, small improvements that can each be implemented by editing a single file.

For each improvement, return a JSON array with objects containing:
- "title": concise issue title
- "body": description with specific file path and what to change
- "file": the file path to edit
- "type": "bug" | "enhancement" | "docs"

Focus on:
- Missing error messages or user guidance
- Documentation gaps
- Small UX improvements in the rendered HTML

IMPORTANT: Use full file paths like "src/adapters/mars_http/server.mbt" or "src/core/api_state.mbt" or "README.md".

Return ONLY the JSON array. No markdown, no explanation.`,
    },
    {
      role: "user",
      content: codeContext,
    },
  ], 1024);

  console.log("\nAnalyst suggestions:\n" + analysis + "\n");

  let suggestions: Array<{
    title: string;
    body: string;
    file: string;
    type: string;
  }>;
  try {
    suggestions = JSON.parse(
      analysis.replace(/```json?\n?/g, "").replace(/```/g, "").trim(),
    );
  } catch {
    console.error("Failed to parse analyst response, using fallback");
    suggestions = [
      {
        title: "Add 404 page with navigation links",
        body: "When a user hits an unknown route, the 404 page just says 'Not Found'. Add navigation links so users can find their way back. Edit src/adapters/mars_http/server.mbt.",
        file: "src/adapters/mars_http/server.mbt",
        type: "enhancement",
      },
    ];
  }

  const issueIds: string[] = [];
  for (const s of suggestions) {
    console.log(`Creating issue: "${s.title}"`);
    const result = await post(
      "/api/issues",
      { title: s.title, body: s.body, author: "analyst-alice" },
      ANALYST_TOKEN,
    );
    issueIds.push(result.id as string);
    console.log(`  → Issue #${result.id}`);
  }

  return issueIds;
}

// ---- Phase 2: Developer ----

async function implementIssue(issueId: string): Promise<void> {
  console.log(`\n--- Developer: working on Issue #${issueId} ---`);

  // Read the issue
  const issueText = await getText(`/issues/${issueId}`);
  const issuePreview = issueText.slice(0, 800);

  // Ask LLM to determine target file
  const fileDecision = await llm([
    {
      role: "system",
      content: `Given an issue description, determine which single file should be edited.
The project has these key files:
- src/adapters/mars_http/server.mbt (HTTP routes and rendering)
- src/core/api_state.mbt (data layer, Storage operations)
- src/core/storage.mbt (Storage trait)
- src/core/ci.mbt (CI run tracking)
- README.md
- CONTRIBUTING.md

Return ONLY the file path (e.g., "src/core/api_state.mbt"). Nothing else.`,
    },
    { role: "user", content: issuePreview.slice(0, 400) },
  ], 100);

  const targetFile = fileDecision.trim().replace(/["`']/g, "");
  if (!targetFile || targetFile.length < 3) {
    console.log("  Could not determine target file, skipping");
    await post(
      `/api/issues/${issueId}/comments`,
      { body: "Could not determine which file to edit.", author: "dev-bob" },
      DEV_TOKEN,
    );
    return;
  }

  console.log(`  Target file: ${targetFile}`);

  // Read current file content
  const currentContent = await getFile(targetFile);
  if (!currentContent) {
    console.log(`  File not found: ${targetFile}`);
    return;
  }

  // Ask LLM to implement the change
  const implementation = await llm([
    {
      role: "system",
      content: `You are a developer implementing a code change.
You will receive an issue description and the current file content.
Return ONLY the complete updated file content. No explanations, no code fences.
Make minimal, targeted changes - don't rewrite the entire file.
If the file is MoonBit (.mbt), maintain the existing code style with ///| separators.`,
    },
    {
      role: "user",
      content: `Issue #${issueId}:
${issuePreview.slice(0, 400)}

Current content of ${targetFile} (first 1500 chars):
${currentContent.slice(0, 1500)}

Implement the change described in the issue. Return the complete updated file.`,
    },
  ], 4096);

  if (implementation.length < 50) {
    console.log("  LLM returned too little content, skipping");
    return;
  }

  console.log(`  Generated ${implementation.length} chars`);

  // Write the file
  const editResult = await post(
    "/api/files",
    {
      path: targetFile,
      content: implementation,
      message: `fix: implement issue #${issueId}`,
      author: "dev-bob",
    },
    DEV_TOKEN,
  );
  console.log("  Edit:", editResult);

  // Create PR
  const prResult = await post(
    "/api/pulls",
    {
      title: `Fix #${issueId}: ${issuePreview.slice(0, 60).replace(/[^a-zA-Z0-9 ]/g, "").trim()}`,
      body: `Implements issue #${issueId}.\n\nChanged: ${targetFile}`,
      base: "main",
      head: `fix-issue-${issueId}`,
      author: "dev-bob",
    },
    DEV_TOKEN,
  );
  console.log("  PR:", prResult);

  // Comment on issue
  await post(
    `/api/issues/${issueId}/comments`,
    {
      body: `Created PR #${prResult.id} with the fix. Changed \`${targetFile}\`.`,
      author: "dev-bob",
    },
    DEV_TOKEN,
  );
  console.log(`  Commented on issue, PR #${prResult.id}`);
}

// ---- Phase 3: Review and merge ----

async function reviewAndMerge(): Promise<void> {
  console.log("\n========================================");
  console.log("Phase 3: Analyst reviews and merges");
  console.log("========================================\n");

  // Get open PRs
  const pullsText = await getText("/pulls");
  const prIds = [...pullsText.matchAll(/#(\d+)/g)].map((m) => m[1]);
  const uniquePrIds = [...new Set(prIds)];

  for (const prId of uniquePrIds) {
    const prText = await getText(`/pulls/${prId}`);
    if (prText.includes("merged") || prText.includes("closed")) continue;
    if (!prText.includes("open")) continue;

    console.log(`Reviewing PR #${prId}...`);

    // LLM review
    const review = await llm([
      {
        role: "system",
        content: "You are reviewing a PR. Give a brief (1-2 sentence) approval comment. Return ONLY the comment text.",
      },
      {
        role: "user",
        content: `PR #${prId}: ${prText.slice(0, 300)}`,
      },
    ], 256);

    console.log(`  Review: ${review.slice(0, 100)}`);

    // Comment
    await post(`/api/pulls/${prId}/comments`, { body: review, author: "analyst-alice" }, ANALYST_TOKEN);

    // Merge
    const mergeResult = await post(`/api/pulls/${prId}/merge`, {}, ANALYST_TOKEN);
    console.log(`  Merged: ${JSON.stringify(mergeResult)}`);
  }

  // Close resolved issues
  const issuesText = await getText("/issues");
  const issueIds = [...issuesText.matchAll(/#(\d+)/g)].map((m) => m[1]);
  for (const id of [...new Set(issueIds)]) {
    const issueText = await getText(`/issues/${id}`);
    if (issueText.includes("closed")) continue;
    if (issueText.includes("PR #")) {
      console.log(`Closing issue #${id} (has PR reference)`);
      await post(`/api/issues/${id}/state`, { state: "closed" }, ANALYST_TOKEN);
    }
  }
}

// ---- Main ----

async function main() {
  console.log("=== Autonomous Improvement Loop ===");
  console.log(`Model: ${MODEL}`);
  console.log(`Bithub: ${BITHUB_URL}\n`);

  // Verify server
  const health = await fetch(`${BITHUB_URL}/healthz`);
  if (!health.ok) {
    console.error("Server not running");
    process.exit(1);
  }

  // Phase 1: Analyze and create issues
  const issueIds = await analyzeAndCreateIssues();

  // Phase 2: Implement each issue
  console.log("\n========================================");
  console.log("Phase 2: Developer implements issues");
  console.log("========================================");

  for (const id of issueIds) {
    await implementIssue(id);
  }

  // Phase 3: Review and merge
  await reviewAndMerge();

  // Summary
  console.log("\n========================================");
  console.log("Summary");
  console.log("========================================\n");
  console.log(`Issues created: ${issueIds.length}`);
  console.log(`Activity: ${BITHUB_URL}/activity`);
  console.log(`Issues: ${BITHUB_URL}/issues`);
  console.log(`PRs: ${BITHUB_URL}/pulls`);
  console.log("\nDone.");
}

main().catch((err) => {
  console.error("Loop failed:", err);
  process.exit(1);
});
