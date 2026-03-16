/**
 * Agent worker: picks up an issue and implements it.
 *
 * Usage:
 *   BITHUB_URL=http://127.0.0.1:4174 ISSUE_ID=1 npx tsx scripts/agent-worker.ts
 */

const BITHUB_URL = process.env.BITHUB_URL || "http://127.0.0.1:4174";
const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY;
const MODEL = process.env.MODEL || "anthropic/claude-sonnet-4";
const ISSUE_ID = process.env.ISSUE_ID || "1";
const AGENT_TOKEN = process.env.AGENT_TOKEN || "tok-bob";
const AGENT_NAME = process.env.AGENT_NAME || "agent-bob";

if (!OPENROUTER_API_KEY) {
  console.error("OPENROUTER_API_KEY required");
  process.exit(1);
}

interface Message {
  role: "system" | "user" | "assistant";
  content: string;
}

async function llm(messages: Message[]): Promise<string> {
  const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENROUTER_API_KEY}`,
    },
    body: JSON.stringify({ model: MODEL, messages, max_tokens: 2048, temperature: 0.2 }),
  });
  const data = (await res.json()) as {
    choices?: Array<{ message?: { content?: string } }>;
    error?: { message?: string };
  };
  if (data.error) throw new Error(`LLM: ${data.error.message}`);
  return data.choices?.[0]?.message?.content || "";
}

async function api(
  method: string,
  path: string,
  body?: Record<string, unknown>,
): Promise<{ status: number; data: Record<string, unknown> }> {
  const opts: RequestInit = {
    method,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${AGENT_TOKEN}`,
    },
  };
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(`${BITHUB_URL}${path}`, opts);
  return { status: res.status, data: (await res.json()) as Record<string, unknown> };
}

async function getText(path: string): Promise<string> {
  const res = await fetch(`${BITHUB_URL}${path}`);
  const html = await res.text();
  return html.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
}

async function main() {
  console.log(`Agent: ${AGENT_NAME}`);
  console.log(`Issue: #${ISSUE_ID}`);
  console.log(`Model: ${MODEL}`);
  console.log(`Bithub: ${BITHUB_URL}\n`);

  // 1. Read the issue
  console.log("--- Reading issue ---");
  const issueText = await getText(`/issues/${ISSUE_ID}`);
  const issuePreview = issueText.slice(0, 600);
  console.log(issuePreview.slice(0, 200) + "...\n");

  // 2. Read existing repo context
  const readmeText = await getText("/file?path=README.md");
  const readmePreview = readmeText.slice(0, 400);

  // 3. Ask LLM to plan and generate the file
  console.log("--- Generating content ---");
  const content = await llm([
    {
      role: "system",
      content: `You are ${AGENT_NAME}, a developer. You implement tasks from issues.
You have access to a bithub repository.
Return ONLY the raw file content. No markdown code fences, no explanations.`,
    },
    {
      role: "user",
      content: `Issue #${ISSUE_ID}:
${issuePreview}

Current README context:
${readmePreview}

The project uses:
- MoonBit (moon check, moon test, moon build --target js)
- pnpm for Node.js (pnpm install, pnpm test:e2e)
- Playwright for E2E tests
- Cloudflare Workers (wrangler deploy)
- just for tasks

Generate the file content that the issue is asking for. Return ONLY the raw content.`,
    },
  ]);
  console.log(`Generated ${content.length} chars\n`);

  // 4. Determine the file path from the issue
  const pathMatch = issueText.match(/CONTRIBUTING\.md|README\.md|[A-Z_]+\.md/);
  const filePath = pathMatch ? pathMatch[0] : "CONTRIBUTING.md";
  console.log(`File: ${filePath}`);

  // 5. Write the file
  console.log("--- Writing file ---");
  const editResult = await api("POST", "/api/files", {
    path: filePath,
    content,
    message: `docs: add ${filePath} (closes #${ISSUE_ID})`,
    author: AGENT_NAME,
  });
  console.log("Edit result:", editResult.data);

  // 6. Create a PR
  console.log("\n--- Creating PR ---");
  const prTitle = await llm([
    {
      role: "system",
      content: "Write a concise PR title (one line, no quotes). Return ONLY the title text.",
    },
    {
      role: "user",
      content: `I added ${filePath} to address issue #${ISSUE_ID}: "${issuePreview.slice(0, 100)}". Write a PR title.`,
    },
  ]);
  console.log("PR title:", prTitle);

  const prResult = await api("POST", "/api/pulls", {
    title: prTitle.trim(),
    body: `Closes #${ISSUE_ID}\n\nAdded ${filePath} with development setup, testing, and deployment instructions.`,
    base: "ccc3456",
    head: "abc1234",
    author: AGENT_NAME,
  });
  console.log("PR created:", prResult.data);

  // 7. Comment on the issue
  console.log("\n--- Commenting on issue ---");
  await api("POST", `/api/issues/${ISSUE_ID}/comments`, {
    body: `I've created PR #${prResult.data.id} with the ${filePath} file. Please review!`,
    author: AGENT_NAME,
  });

  // 8. Print results
  console.log("\n=== Done ===");
  console.log(`File: ${BITHUB_URL}/file?path=${filePath}`);
  console.log(`PR: ${BITHUB_URL}/pulls/${prResult.data.id}`);
  console.log(`Issue: ${BITHUB_URL}/issues/${ISSUE_ID}`);

  // 9. Verify the file was written
  const verify = await getText(`/file?path=${filePath}`);
  const hasContent = verify.length > 200;
  console.log(`\nFile written: ${hasContent ? "YES" : "NO"} (${verify.length} chars)`);

  // 10. Check if it persisted to disk
  const fs = await import("node:fs");
  const diskPath = `/Users/mz/ghq/github.com/bit-vcs/bithub/.bithub/data/${filePath}`;
  const onDisk = fs.existsSync(diskPath);
  console.log(`Persisted to disk: ${onDisk ? "YES" : "NO"} (${diskPath})`);
}

main().catch((err) => {
  console.error("Agent failed:", err);
  process.exit(1);
});
