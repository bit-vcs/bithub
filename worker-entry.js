// Cloudflare Workers entry point wrapper
// Defers MoonBit module initialization to first fetch() call
// to avoid "Disallowed operation in global scope" errors (random seed, etc.)

// MoonBit async runtime requires this global symbol
const rescheduleKey =
  "moonbitlang$async$internal$event_loop$$reschedule";
if (typeof globalThis[rescheduleKey] !== "function") {
  globalThis[rescheduleKey] = () => {};
}

let mod = null;

async function ensureInit() {
  if (mod) return mod;
  mod = await import("./_build/js/debug/build/cmd/main/main.js");
  return mod;
}

// ---- Lazy R2 Storage ----
// Instead of preloading all keys, we provide async get/put/list/head
// that the synchronous R2Storage FFI reads from a per-request cache.
// Only keys actually accessed during the request are loaded.

function setupR2(env) {
  const bucket = env.BITHUB_STORE;
  if (!bucket) return;

  globalThis.__r2_env = { BITHUB_STORE: bucket };
  // Fresh cache per request — no stale data across requests
  globalThis.__r2_cache = {};
  globalThis.__r2_dirty = {};
  globalThis.__r2_list_cache = {};
}

// Preload only the keys needed for this request path
async function preloadForRoute(env, pathname) {
  const bucket = env.BITHUB_STORE;
  if (!bucket) return;

  const cache = globalThis.__r2_cache;
  // Seed default tokens into both R2 and cache
  const defaultTokens = {
    "auth/tokens/tok-owner-001": "identity=admin\nrole=owner",
    "auth/tokens/tok-write-001": "identity=ci-bot\nrole=write",
    "auth/tokens/tok-alice": "identity=agent-alice\nrole=owner",
    "auth/tokens/tok-bob": "identity=agent-bob\nrole=write",
  };
  for (const [key, value] of Object.entries(defaultTokens)) {
    cache["BITHUB_STORE/" + key] = value;
    // Also persist to R2 if not present
    try {
      const existing = await bucket.head(key);
      if (!existing) {
        await bucket.put(key, value);
      }
    } catch {}
  }

  const prefixes = []; // tokens already seeded above

  // Strip /workspace/{id} prefix for route matching
  let routePath = pathname;
  const isWorkspace = pathname.startsWith("/workspace/");
  if (isWorkspace) {
    const rest = pathname.slice("/workspace/".length);
    const slash = rest.indexOf("/");
    routePath = slash >= 0 ? rest.slice(slash) : "/filer";
  }

  // Workspace is a full SPA — all data from IndexedDB, no R2 needed
  if (isWorkspace) return;

  // Route-based prefixes
  if (routePath.startsWith("/issues") || routePath === "/activity") {
    prefixes.push("issues/");
  }
  if (routePath.startsWith("/pulls") || routePath === "/activity") {
    prefixes.push("prs/");
  }
  if (routePath.startsWith("/actions") || pathname.startsWith("/api/webhook")) {
    prefixes.push("ci/", ".github/workflows/");
  }
  if (routePath.startsWith("/commits") || routePath.startsWith("/commit/")) {
    prefixes.push("git/commits/");
  }
  if (routePath === "/branches") {
    prefixes.push("git/branches/");
  }
  if (routePath === "/tags") {
    prefixes.push("git/tags/");
  }
  if (routePath.startsWith("/webhooks")) {
    prefixes.push("webhooks/");
  }
  if (routePath === "/stats" || routePath === "/activity") {
    prefixes.push(
      "git/commits/",
      "git/branches/",
      "issues/",
      "prs/",
    );
  }
  if (
    routePath.startsWith("/filer") ||
    routePath.startsWith("/search") ||
    routePath.startsWith("/blame")
  ) {
    // Filer needs all repo files — load everything
    prefixes.push("");
  } else if (
    routePath.startsWith("/file") ||
    routePath.startsWith("/readme") ||
    routePath === "/"
  ) {
    // Single file view — load common files
    prefixes.push("README.md");
  }
  if (pathname.startsWith("/api/files") || pathname.startsWith("/api/issues") || pathname.startsWith("/api/pulls") || pathname.startsWith("/api/trigger")) {
    // Write endpoints — need auth + target data
    prefixes.push("auth/tokens/");
  }

  // Load each prefix
  const loaded = new Set();
  for (const prefix of prefixes) {
    if (loaded.has(prefix)) continue;
    loaded.add(prefix);

    try {
      // Single key (e.g. "README.md") — but "" means list all
      if (prefix !== "" && !prefix.endsWith("/")) {
        const obj = await bucket.get(prefix);
        if (obj) {
          cache["BITHUB_STORE/" + prefix] = await obj.text();
        }
        continue;
      }

      // Prefix listing (empty prefix = list all)
      const listOpts = prefix ? { prefix, limit: 500 } : { limit: 500 };
      let cursor = undefined;
      let count = 0;
      do {
        const listed = await bucket.list({ ...listOpts, cursor });
        for (const obj of listed.objects) {
          if (count >= 500) break;
          const body = await bucket.get(obj.key);
          if (body) {
            cache["BITHUB_STORE/" + obj.key] = await body.text();
            count++;
          }
        }
        cursor = listed.truncated ? listed.cursor : undefined;
      } while (cursor && count < 500);
    } catch {}
  }
}

// Flush dirty cache entries back to R2
async function flushR2(env) {
  const bucket = env.BITHUB_STORE;
  if (!bucket) return;

  const dirty = globalThis.__r2_dirty;
  if (!dirty) return;

  const cache = globalThis.__r2_cache || {};
  const promises = [];
  for (const key of Object.keys(dirty)) {
    const fullKey = "BITHUB_STORE/" + key;
    if (fullKey in cache) {
      promises.push(bucket.put(key, cache[fullKey]));
    }
  }
  if (promises.length > 0) {
    await Promise.all(promises);
  }
  globalThis.__r2_dirty = {};
}

// ---- GitHub API helpers for repo initialization ----
// Use env var or default; workers.dev → workers.dev subrequests may
// need a custom domain to avoid Cloudflare's same-zone restrictions.
function relayBase(env) {
  return env?.BIT_RELAY_URL || "https://bit-relay.mizchi.workers.dev";
}

async function handleApiInit(request, env) {
  const url = new URL(request.url);
  const repo = url.searchParams.get("repo"); // owner/repo
  if (!repo || !repo.includes("/")) {
    return Response.json({ error: "missing ?repo=owner/repo" }, { status: 400 });
  }
  const bucket = env.BITHUB_STORE;
  if (!bucket) {
    return Response.json({ error: "R2 not configured" }, { status: 503 });
  }

  const [owner, name] = repo.split("/");
  const ghApi = `https://api.github.com/repos/${owner}/${name}`;
  const headers = { "User-Agent": "bithub/0.1", Accept: "application/vnd.github.v3+json" };
  const ghToken = env.GITHUB_TOKEN;
  if (ghToken) headers.Authorization = `Bearer ${ghToken}`;

  try {
    // 1. Get default branch
    const repoRes = await fetch(ghApi, { headers });
    if (!repoRes.ok) {
      const body = await repoRes.text();
      return Response.json({ error: `GitHub: ${repoRes.status}`, body: body.slice(0, 200) }, { status: 502 });
    }
    const repoData = await repoRes.json();
    const defaultBranch = repoData.default_branch || "main";

    // 2. Get tree (recursive)
    const treeRes = await fetch(`${ghApi}/git/trees/${defaultBranch}?recursive=1`, { headers });
    if (!treeRes.ok) return Response.json({ error: `GitHub tree: ${treeRes.status}` }, { status: 502 });
    const treeData = await treeRes.json();

    // 3. Store tree metadata
    let fileCount = 0;
    const MAX_FILES = 100;
    const MAX_FILE_SIZE = 100_000; // 100KB

    for (const entry of treeData.tree || []) {
      if (entry.type !== "blob" || fileCount >= MAX_FILES) continue;
      if (entry.size > MAX_FILE_SIZE) continue;

      // Fetch file content
      try {
        const blobRes = await fetch(`${ghApi}/git/blobs/${entry.sha}`, { headers });
        if (!blobRes.ok) continue;
        const blobData = await blobRes.json();
        let content;
        if (blobData.encoding === "base64") {
          const binary = Uint8Array.from(atob(blobData.content.replace(/\n/g, "")), c => c.charCodeAt(0));
          content = new TextDecoder("utf-8").decode(binary);
        } else {
          content = blobData.content;
        }
        await bucket.put(entry.path, content);
        fileCount++;
      } catch { /* skip individual file errors */ }
    }

    // 4. Store repo metadata
    await bucket.put("_meta/repo", JSON.stringify({
      owner, name, default_branch: defaultBranch,
      initialized_at: new Date().toISOString(),
      file_count: fileCount,
    }));

    // 5. Get HEAD commit only (--depth 1)
    const commitsRes = await fetch(`${ghApi}/commits?sha=${defaultBranch}&per_page=1`, { headers });
    if (commitsRes.ok) {
      const commits = await commitsRes.json();
      if (commits.length > 0) {
        const c = commits[0];
        const meta = [
          `message=${c.commit.message.split("\n")[0]}`,
          `author=${c.commit.author.name}`,
          `timestamp=${Math.floor(new Date(c.commit.author.date).getTime() / 1000)}`,
          `parent=`,
        ].join("\n");
        await bucket.put(`git/commits/${c.sha}`, meta);
      }
    }

    // 6. Store only default branch (--depth 1, main branch only)
    const branchRes = await fetch(`${ghApi}/branches/${defaultBranch}`, { headers });
    if (branchRes.ok) {
      const branch = await branchRes.json();
      await bucket.put(`git/branches/${defaultBranch}`, branch.commit.sha);
      await bucket.put("git/HEAD", `ref: refs/heads/${defaultBranch}`);
    }

    return Response.json({
      ok: true,
      repo,
      default_branch: defaultBranch,
      files: fileCount,
    });
  } catch (err) {
    return Response.json({ error: err.message }, { status: 500 });
  }
}

async function relayFetch(env, path) {
  // Use Service Binding if available, otherwise external fetch
  if (env.BIT_RELAY) {
    return env.BIT_RELAY.fetch(new Request(`https://bit-relay/${path}`));
  }
  return fetch(`${relayBase(env)}/${path}`);
}

async function handleApiParticipants(request, env) {
  const url = new URL(request.url);
  const repo = url.searchParams.get("repo") || "";
  const room = repo || "default";
  try {
    const res = await relayFetch(env, `api/v1/presence?room=${room}`);
    return new Response(res.body, { status: res.status, headers: { "content-type": "application/json" } });
  } catch {
    return Response.json({ error: "relay unreachable" }, { status: 502 });
  }
}

async function handleApiActivity(request, env) {
  const url = new URL(request.url);
  const repo = url.searchParams.get("repo") || "";
  const after = url.searchParams.get("after") || "0";
  const room = repo || "default";
  try {
    const res = await relayFetch(env, `api/v1/poll?room=${room}&after=${after}&limit=50`);
    return new Response(res.body, { status: res.status, headers: { "content-type": "application/json" } });
  } catch {
    return Response.json({ error: "relay unreachable" }, { status: 502 });
  }
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Handle special API routes before MoonBit
    if (url.pathname === "/api/init" && request.method === "POST") {
      return handleApiInit(request, env);
    }
    if (url.pathname === "/api/participants") {
      return handleApiParticipants(request, env);
    }
    if (url.pathname === "/api/activity") {
      return handleApiActivity(request, env);
    }

    setupR2(env);
    await preloadForRoute(env, url.pathname);
    const m = await ensureInit();
    const response = await m.fetch(request, env, ctx);
    ctx.waitUntil(flushR2(env));
    return response;
  },
};
