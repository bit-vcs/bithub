/**
 * Create a bithub issue from command line.
 *
 * Usage:
 *   pnpm issue:create "Title" "Body text"
 *   pnpm issue:create "Title"                    # body is optional
 *   echo "body" | pnpm issue:create "Title" -    # read body from stdin
 */

const BITHUB_URL = process.env.BITHUB_URL || "http://127.0.0.1:4174";
const TOKEN = process.env.AGENT_TOKEN || "tok-alice";

async function readStdin(): Promise<string> {
  const chunks: string[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk.toString());
  }
  return chunks.join("");
}

async function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    console.log("Usage: pnpm issue:create \"Title\" [\"Body\" | -]");
    console.log("");
    console.log("Examples:");
    console.log('  pnpm issue:create "Fix the bug"');
    console.log('  pnpm issue:create "Add tests" "Create tests for xml_escape"');
    console.log('  echo "details" | pnpm issue:create "Title" -');
    process.exit(1);
  }

  const title = args[0];
  let body = args[1] || "";

  if (body === "-") {
    body = await readStdin();
  }

  const res = await fetch(`${BITHUB_URL}/api/issues`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${TOKEN}`,
    },
    body: JSON.stringify({ title, body }),
  });

  const data = (await res.json()) as Record<string, unknown>;
  if (data.id) {
    console.log(`Created issue #${data.id}: ${title}`);
    console.log(`${BITHUB_URL}/issues/${data.id}`);
  } else {
    console.error("Failed:", data);
    process.exit(1);
  }
}

main();
