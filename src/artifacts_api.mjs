const REPOSITORY_NAME_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;
const SHA1_PATTERN = /^[a-f0-9]{40}$/i;

function jsonError(error, status) {
  return Response.json({ ok: false, error }, { status });
}

function timingSafeEqual(left, right) {
  if (left.length !== right.length) return false;
  let mismatch = 0;
  for (let index = 0; index < left.length; index += 1) {
    mismatch |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return mismatch === 0;
}

function hasBearerToken(request, expectedToken) {
  const authorization = (request.headers.get('authorization') ?? '').trim();
  const matched = authorization.match(/^Bearer\s+(.+)$/i);
  const token = matched?.[1]?.trim();
  return typeof token === 'string' && timingSafeEqual(token, expectedToken);
}

function boundedInteger(value, defaultValue, min, max) {
  if (value === null) return defaultValue;
  if (!/^(0|[1-9][0-9]*)$/.test(value)) return null;
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < min || parsed > max) return null;
  return parsed;
}

function validRef(value) {
  return value.length > 0 && value.length <= 256 && !/[\u0000-\u001f\u007f]/.test(value);
}

function isArtifactsPath(pathname) {
  return pathname === '/api/artifacts/repos' || pathname.startsWith('/api/artifacts/repos/');
}

/**
 * Read-only adapter from bithub HTTP routes to the Cloudflare Artifacts binding.
 * It intentionally never mints or returns a Git credential.
 */
export async function handleArtifactsApi(request, env) {
  const url = new URL(request.url);
  if (!isArtifactsPath(url.pathname)) return null;
  if (request.method !== 'GET') return jsonError('method not allowed', 405);

  const expectedToken = (env?.BITHUB_ARTIFACTS_READ_TOKEN ?? '').trim();
  if (expectedToken.length === 0) {
    return jsonError('artifacts browse API is not configured', 503);
  }
  if (!hasBearerToken(request, expectedToken)) return jsonError('unauthorized', 401);
  if (!env?.ARTIFACTS) return jsonError('artifacts binding is not configured', 503);

  const listLimit = boundedInteger(url.searchParams.get('limit'), 20, 1, 100);
  if (listLimit === null) return jsonError('limit must be an integer between 1 and 100', 400);

  try {
    if (url.pathname === '/api/artifacts/repos') {
      const cursor = url.searchParams.get('cursor') || undefined;
      const page = await env.ARTIFACTS.list({ limit: listLimit, cursor });
      return Response.json({ ok: true, repos: page.repos, cursor: page.cursor ?? null });
    }

    const logMatch = url.pathname.match(/^\/api\/artifacts\/repos\/([A-Za-z0-9][A-Za-z0-9._-]{0,63})\/log$/);
    const commitMatch = url.pathname.match(
      /^\/api\/artifacts\/repos\/([A-Za-z0-9][A-Za-z0-9._-]{0,63})\/commits\/([^/]+)$/,
    );
    const treeMatch = url.pathname.match(
      /^\/api\/artifacts\/repos\/([A-Za-z0-9][A-Za-z0-9._-]{0,63})\/trees\/([^/]+)$/,
    );

    if (!logMatch && !commitMatch && !treeMatch) return jsonError('not found', 404);
    const repository = (logMatch ?? commitMatch ?? treeMatch)[1];
    if (!REPOSITORY_NAME_PATTERN.test(repository)) return jsonError('invalid repository name', 400);

    if (logMatch) {
      const ref = url.searchParams.get('ref') ?? 'main';
      if (!validRef(ref)) return jsonError('invalid ref', 400);
      const limit = boundedInteger(url.searchParams.get('limit'), 20, 1, 100);
      const offset = boundedInteger(url.searchParams.get('offset'), 0, 0, 10_000);
      if (limit === null) return jsonError('limit must be an integer between 1 and 100', 400);
      if (offset === null) return jsonError('offset must be an integer between 0 and 10000', 400);
      const repo = await env.ARTIFACTS.get(repository);
      const log = await repo.log({ ref, limit, offset });
      return Response.json({ ok: true, repo: repository, log });
    }

    const hash = (commitMatch ?? treeMatch)[2];
    if (!SHA1_PATTERN.test(hash)) return jsonError('invalid object hash', 400);
    const repo = await env.ARTIFACTS.get(repository);
    if (commitMatch) {
      const commit = await repo.readCommit(hash);
      return Response.json({ ok: true, repo: repository, commit });
    }
    const tree = await repo.readTree(hash);
    return Response.json({ ok: true, repo: repository, tree });
  } catch {
    // A binding exception can mean an absent, non-ready, or inaccessible repo.
    return jsonError('artifacts repository is unavailable', 502);
  }
}
