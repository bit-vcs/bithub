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

// Preload R2 data into the synchronous cache used by R2Storage
async function preloadR2(env) {
  const bucket = env.BITHUB_STORE;
  if (!bucket) return;

  // Expose R2 env for async writes
  globalThis.__r2_env = { BITHUB_STORE: bucket };
  if (!globalThis.__r2_cache) globalThis.__r2_cache = {};

  // Load all keys into cache for synchronous access
  let cursor = undefined;
  let count = 0;
  const limit = 500;
  do {
    const listed = await bucket.list({ cursor, limit: 1000 });
    for (const obj of listed.objects) {
      if (count >= limit) break;
      const body = await bucket.get(obj.key);
      if (body) {
        globalThis.__r2_cache["BITHUB_STORE/" + obj.key] = await body.text();
        count++;
      }
    }
    cursor = listed.truncated ? listed.cursor : undefined;
  } while (cursor && count < limit);
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
    await preloadR2(env);
    const m = await ensureInit();
    const response = await m.fetch(request, env, ctx);
    // Flush writes to R2 in background
    ctx.waitUntil(flushR2(env));
    return response;
  },
};
