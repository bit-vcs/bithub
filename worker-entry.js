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

export default {
  async fetch(request, env, ctx) {
    const m = await ensureInit();
    return m.fetch(request, env, ctx);
  },
};
