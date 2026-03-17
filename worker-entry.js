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

  // Route-based prefixes
  if (pathname.startsWith("/issues") || pathname === "/activity") {
    prefixes.push("issues/");
  }
  if (pathname.startsWith("/pulls") || pathname === "/activity") {
    prefixes.push("prs/");
  }
  if (pathname.startsWith("/actions") || pathname.startsWith("/api/webhook")) {
    prefixes.push("ci/", ".github/workflows/");
  }
  if (pathname.startsWith("/commits") || pathname.startsWith("/commit/")) {
    prefixes.push("git/commits/");
  }
  if (pathname === "/branches") {
    prefixes.push("git/branches/");
  }
  if (pathname === "/tags") {
    prefixes.push("git/tags/");
  }
  if (pathname.startsWith("/webhooks")) {
    prefixes.push("webhooks/");
  }
  if (pathname === "/stats" || pathname === "/activity") {
    prefixes.push(
      "git/commits/",
      "git/branches/",
      "issues/",
      "prs/",
    );
  }
  if (
    pathname.startsWith("/file") ||
    pathname.startsWith("/filer") ||
    pathname.startsWith("/search") ||
    pathname.startsWith("/blame") ||
    pathname.startsWith("/readme") ||
    pathname === "/"
  ) {
    // Need file content — load common files
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
      // Single key (e.g. "README.md")
      if (!prefix.endsWith("/")) {
        const obj = await bucket.get(prefix);
        if (obj) {
          cache["BITHUB_STORE/" + prefix] = await obj.text();
        }
        continue;
      }

      // Prefix listing
      let cursor = undefined;
      let count = 0;
      do {
        const listed = await bucket.list({ prefix, cursor, limit: 200 });
        for (const obj of listed.objects) {
          if (count >= 200) break;
          const body = await bucket.get(obj.key);
          if (body) {
            cache["BITHUB_STORE/" + obj.key] = await body.text();
            count++;
          }
        }
        cursor = listed.truncated ? listed.cursor : undefined;
      } while (cursor && count < 200);
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

export default {
  async fetch(request, env, ctx) {
    setupR2(env);
    const url = new URL(request.url);
    await preloadForRoute(env, url.pathname);
    const m = await ensureInit();
    const response = await m.fetch(request, env, ctx);
    ctx.waitUntil(flushR2(env));
    return response;
  },
};
