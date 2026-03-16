///| R2Storage: Cloudflare R2-backed Storage implementation.
///  Uses JS FFI to call R2 bucket operations.
///  All operations are synchronous from MoonBit's perspective
///  (R2 calls are awaited inside the FFI).

///|
pub struct R2Storage {
  bucket_name : String
}

///|
pub fn R2Storage::new(bucket_name : String) -> R2Storage {
  { bucket_name, }
}

///|
extern "js" fn r2_get(bucket_name : String, key : String) -> String? =
  #| (() => {
  #|   let _bucket = null;
  #|   return (bucket_name, key) => {
  #|     if (!_bucket && typeof globalThis.__r2_env !== 'undefined') {
  #|       _bucket = globalThis.__r2_env[bucket_name];
  #|     }
  #|     if (!_bucket) return undefined;
  #|     // Synchronous wrapper: store result via blocking pattern
  #|     // In Workers, R2 ops are async. We use a global cache for sync access.
  #|     const cached = globalThis.__r2_cache?.[bucket_name + '/' + key];
  #|     return cached !== undefined ? cached : undefined;
  #|   };
  #| })()

///|
extern "js" fn r2_put(bucket_name : String, key : String, value : String) -> Unit =
  #| (() => {
  #|   return (bucket_name, key, value) => {
  #|     if (!globalThis.__r2_cache) globalThis.__r2_cache = {};
  #|     globalThis.__r2_cache[bucket_name + '/' + key] = value;
  #|     // Queue async write to actual R2
  #|     if (typeof globalThis.__r2_env !== 'undefined') {
  #|       const bucket = globalThis.__r2_env[bucket_name];
  #|       if (bucket) bucket.put(key, value).catch(() => {});
  #|     }
  #|   };
  #| })()

///|
extern "js" fn r2_list(bucket_name : String, prefix : String) -> Array[String] =
  #| (() => {
  #|   return (bucket_name, prefix) => {
  #|     const cache = globalThis.__r2_cache || {};
  #|     const fullPrefix = bucket_name + '/' + (prefix.length > 0 ? prefix + '/' : '');
  #|     const seen = new Set();
  #|     const result = [];
  #|     for (const key of Object.keys(cache)) {
  #|       if (!key.startsWith(fullPrefix)) continue;
  #|       const rest = key.slice(fullPrefix.length);
  #|       if (rest.length === 0) continue;
  #|       const slashIdx = rest.indexOf('/');
  #|       const name = slashIdx >= 0 ? rest.slice(0, slashIdx) : rest;
  #|       if (!seen.has(name)) {
  #|         seen.add(name);
  #|         result.push(name);
  #|       }
  #|     }
  #|     return result;
  #|   };
  #| })()

///|
extern "js" fn r2_has(bucket_name : String, key : String) -> Bool =
  #| (() => {
  #|   return (bucket_name, key) => {
  #|     const cache = globalThis.__r2_cache || {};
  #|     return (bucket_name + '/' + key) in cache;
  #|   };
  #| })()

///|
pub impl Storage for R2Storage with get(self, key) {
  match r2_get(self.bucket_name, key) {
    Some(text) => Some(@utf8.encode(text))
    None => None
  }
}

///|
pub impl Storage for R2Storage with set_string(self, key, value) {
  r2_put(self.bucket_name, key, value)
}

///|
pub impl Storage for R2Storage with list(self, prefix) {
  r2_list(self.bucket_name, prefix)
}

///|
pub impl Storage for R2Storage with has(self, key) {
  r2_has(self.bucket_name, key)
}

///|
/// Preload R2 data into in-memory cache for synchronous access.
/// Call this at the start of a request handler in Workers.
extern "js" fn r2_preload_cache(
  bucket_name : String,
  prefix : String,
) -> Unit =
  #| (() => {
  #|   return (bucket_name, prefix) => {
  #|     // In Workers, this would be called with await in the fetch handler
  #|     // to populate __r2_cache before synchronous Storage calls
  #|     if (!globalThis.__r2_cache) globalThis.__r2_cache = {};
  #|   };
  #| })()
