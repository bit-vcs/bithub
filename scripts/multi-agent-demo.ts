/**
 * Multi-agent collaboration demo using OpenRouter LLM.
 *
 * Two agents (Alice and Bob) collaborate on a bithub repo:
 * - Alice: owner, creates issues and reviews PRs
 * - Bob: writer, implements tasks and creates PRs
 *
 * Usage:
 *   BITHUB_URL=http://127.0.0.1:4174 npx tsx scripts/multi-agent-demo.ts
 */

const BITHUB_URL = process.env.BITHUB_URL || "http://127.0.0.1:4174";
const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY;
const MODEL = process.env.MODEL || "anthropic/claude-sonnet-4";

if (!OPENROUTER_API_KEY) {
  console.error("OPENROUTER_API_KEY is required");
  process.exit(1);
}

// Agent tokens
const ALICE_TOKEN = "tok-alice";
const BOB_TOKEN = "tok-bob";

// ---- Bithub API helpers ----

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

async function bithubGet(path: string): Promise<string> {
  const res = await fetch(`${BITHUB_URL}${path}`);
  return res.text();
}

// ---- OpenRouter LLM call ----

interface Message {
  role: "system" | "user" | "assistant";
  content: string;
}

async function llmCall(messages: Message[]): Promise<string> {
  const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENROUTER_API_KEY}`,
    },
    body: JSON.stringify({
      model: MODEL,
      messages,
      max_tokens: 1024,
      temperature: 0.3,
    }),
  });
  const data = (await res.json()) as {
    choices?: Array<{ message?: { content?: string } }>;
    error?: { message?: string };
  };
  if (data.error) {
    throw new Error(`LLM error: ${data.error.message}`);
  }
  return data.choices?.[0]?.message?.content || "";
}

// ---- Agent definitions ----

const BITHUB_API_SPEC = `
Bithub API (base: ${BITHUB_URL}):
- POST /api/issues {title, body} → {id}
- POST /api/issues/:id/comments {body} → {ok}
- POST /api/issues/:id/state {state: "open"|"closed"} → {ok}
- POST /api/files {path, content, message} → {ok, commit_sha}
- POST /api/pulls {title, body, base, head} → {id}
- POST /api/pulls/:id/comments {body} → {ok}
- POST /api/pulls/:id/merge {} → {ok}
- GET /issues/:id → HTML page
- GET /file?path=X → HTML page
- GET /commits → HTML page
`;

async function agentAliceCreateIssue(): Promise<string> {
  console.log("\n=== Alice: Creating issue ===");
  const response = await llmCall([
    {
      role: "system",
      content: `You are agent-alice, a project owner for bithub. You need to create an issue asking someone to improve the README.md file. Return ONLY a JSON object with "title" and "body" fields. No markdown, no explanation.`,
    },
    {
      role: "user",
      content: `The current README.md just says "# bithub" and a brief description. Create an issue asking to add a proper features section, installation instructions, and usage examples. Return JSON only.`,
    },
  ]);
  console.log("Alice LLM response:", response);

  const parsed = JSON.parse(response.replace(/```json?\n?/g, "").replace(/```/g, "").trim());
  const result = await bithubPost("/api/issues", parsed, ALICE_TOKEN);
  console.log("Issue created:", result);
  return result.id as string;
}

async function agentBobReadAndImplement(issueId: string): Promise<{ commitSha: string }> {
  console.log("\n=== Bob: Reading issue and implementing ===");

  // Read the issue
  const issueHtml = await bithubGet(`/issues/${issueId}`);
  const issueText = issueHtml.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").slice(0, 500);
  console.log("Issue preview:", issueText.slice(0, 200));

  // Ask LLM to generate the file content
  const response = await llmCall([
    {
      role: "system",
      content: `You are agent-bob, a developer. You read an issue and need to write a new README.md. Return ONLY the raw markdown content for README.md. No JSON wrapping, no code fences.`,
    },
    {
      role: "user",
      content: `Issue: ${issueText}\n\nWrite a new README.md for "bithub" - a GitHub-like platform built with MoonBit. Include: project title, description, features list, quick start, and API overview. Keep it concise (under 50 lines).`,
    },
  ]);
  console.log("Bob generated README (" + response.length + " chars)");

  // Edit the file
  const editResult = await bithubPost(
    "/api/files",
    {
      path: "README.md",
      content: response,
      message: `docs: improve README with features and usage (fixes #${issueId})`,
    },
    BOB_TOKEN,
  );
  console.log("File edited:", editResult);
  return { commitSha: editResult.commit_sha as string };
}

async function agentBobCreatePR(issueId: string): Promise<string> {
  console.log("\n=== Bob: Creating PR ===");
  const response = await llmCall([
    {
      role: "system",
      content: `You are agent-bob. Write a PR description for improving the README. Return ONLY a JSON object with "title" and "body" fields. Reference issue #${issueId}.`,
    },
    {
      role: "user",
      content: `You improved the README.md with features, quick start, and API overview. Write a concise PR title and body. Return JSON only.`,
    },
  ]);
  console.log("Bob PR response:", response);

  const parsed = JSON.parse(response.replace(/```json?\n?/g, "").replace(/```/g, "").trim());
  const result = await bithubPost(
    "/api/pulls",
    { ...parsed, base: "ccc3456", head: "abc1234" },
    BOB_TOKEN,
  );
  console.log("PR created:", result);
  return result.id as string;
}

async function agentAliceReview(prId: string): Promise<string> {
  console.log("\n=== Alice: Reviewing PR ===");

  // Read PR
  const prHtml = await bithubGet(`/pulls/${prId}`);
  const prText = prHtml.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").slice(0, 500);

  // Read the current README
  const readmeHtml = await bithubGet("/file?path=README.md");
  const readmeText = readmeHtml.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").slice(0, 800);

  const response = await llmCall([
    {
      role: "system",
      content: `You are agent-alice, reviewing a PR. Give brief, constructive feedback. Return ONLY the review comment text (1-3 sentences). No JSON.`,
    },
    {
      role: "user",
      content: `PR: ${prText.slice(0, 200)}\n\nREADME content: ${readmeText.slice(0, 400)}\n\nGive a brief review comment.`,
    },
  ]);
  console.log("Alice review:", response);

  await bithubPost(`/api/pulls/${prId}/comments`, { body: response }, ALICE_TOKEN);
  return response;
}

async function agentAliceMerge(prId: string, issueId: string): Promise<void> {
  console.log("\n=== Alice: Merging PR and closing issue ===");
  const mergeResult = await bithubPost(`/api/pulls/${prId}/merge`, {}, ALICE_TOKEN);
  console.log("Merge:", mergeResult);

  const closeResult = await bithubPost(`/api/issues/${issueId}/state`, { state: "closed" }, ALICE_TOKEN);
  console.log("Close issue:", closeResult);
}

// ---- Main flow ----

async function main() {
  console.log("=== Multi-Agent Collaboration Demo ===");
  console.log(`Bithub: ${BITHUB_URL}`);
  console.log(`Model: ${MODEL}`);
  console.log("");

  // Verify server is running
  try {
    const health = await fetch(`${BITHUB_URL}/healthz`);
    if (!health.ok) throw new Error("Server not healthy");
  } catch {
    console.error(`Cannot reach ${BITHUB_URL}. Start the server first.`);
    process.exit(1);
  }

  // 1. Alice creates issue
  const issueId = await agentAliceCreateIssue();

  // 2. Bob reads issue and implements
  await agentBobReadAndImplement(issueId);

  // 3. Bob creates PR
  const prId = await agentBobCreatePR(issueId);

  // 4. Alice reviews
  await agentAliceReview(prId);

  // 5. Alice merges and closes
  await agentAliceMerge(prId, issueId);

  // 6. Verify final state
  console.log("\n=== Verification ===");
  const activityHtml = await bithubGet("/activity");
  const eventCount = (activityHtml.match(/<tr>/g) || []).length - 1; // subtract header
  console.log(`Activity events: ${eventCount}`);

  const readmeHtml = await bithubGet("/file?path=README.md");
  const hasFeatures = readmeHtml.includes("Features") || readmeHtml.includes("features");
  console.log(`README has features section: ${hasFeatures}`);

  console.log("\n=== Demo complete ===");
  console.log(`Issue: ${BITHUB_URL}/issues/${issueId}`);
  console.log(`PR: ${BITHUB_URL}/pulls/${prId}`);
  console.log(`Activity: ${BITHUB_URL}/activity`);
}

main().catch((err) => {
  console.error("Demo failed:", err);
  process.exit(1);
});
