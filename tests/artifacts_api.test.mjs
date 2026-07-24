import assert from 'node:assert/strict';
import test from 'node:test';
import { handleArtifactsApi } from '../src/artifacts_api.mjs';

function createArtifactsBinding() {
  const calls = [];
  const repo = {
    async log(options) {
      calls.push({ method: 'log', options });
      return { commits: [{ hash: 'a'.repeat(40), message: 'Initial commit' }] };
    },
    async readCommit(hash) {
      calls.push({ method: 'readCommit', hash });
      return { hash, tree: 'b'.repeat(40), message: 'Initial commit' };
    },
    async readTree(hash) {
      calls.push({ method: 'readTree', hash });
      return { hash, entries: [{ path: 'README.md', type: 'blob' }] };
    },
  };
  return {
    binding: {
      async get(name) {
        calls.push({ method: 'get', name });
        return repo;
      },
      async list(options) {
        calls.push({ method: 'list', options });
        return { repos: [{ name: 'demo', status: 'ready' }], cursor: null };
      },
    },
    calls,
  };
}

const authorizedEnv = (binding) => ({
  ARTIFACTS: binding,
  BITHUB_ARTIFACTS_READ_TOKEN: 'bithub-reader-secret',
});

test('artifacts browse API is disabled until its dedicated read token is configured', async () => {
  const { binding } = createArtifactsBinding();
  const response = await handleArtifactsApi(
    new Request('https://bithub.example/api/artifacts/repos'),
    { ARTIFACTS: binding },
  );

  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), {
    ok: false,
    error: 'artifacts browse API is not configured',
  });
});

test('artifacts browse API rejects callers without its dedicated bearer token', async () => {
  const { binding } = createArtifactsBinding();
  const response = await handleArtifactsApi(
    new Request('https://bithub.example/api/artifacts/repos'),
    authorizedEnv(binding),
  );

  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { ok: false, error: 'unauthorized' });
});

test('artifacts browse API lists repositories and reads commit, tree data without exposing a git token', async () => {
  const { binding, calls } = createArtifactsBinding();
  const env = authorizedEnv(binding);
  const headers = { authorization: 'Bearer bithub-reader-secret' };

  const list = await handleArtifactsApi(
    new Request('https://bithub.example/api/artifacts/repos?limit=25', { headers }),
    env,
  );
  assert.equal(list.status, 200);
  assert.deepEqual(await list.json(), {
    ok: true,
    repos: [{ name: 'demo', status: 'ready' }],
    cursor: null,
  });

  const log = await handleArtifactsApi(
    new Request('https://bithub.example/api/artifacts/repos/demo/log?ref=main&limit=5&offset=2', {
      headers,
    }),
    env,
  );
  assert.equal(log.status, 200);
  assert.deepEqual(await log.json(), {
    ok: true,
    repo: 'demo',
    log: { commits: [{ hash: 'a'.repeat(40), message: 'Initial commit' }] },
  });

  const commit = await handleArtifactsApi(
    new Request(`https://bithub.example/api/artifacts/repos/demo/commits/${'a'.repeat(40)}`, {
      headers,
    }),
    env,
  );
  assert.equal(commit.status, 200);
  assert.equal((await commit.json()).commit.tree, 'b'.repeat(40));

  const tree = await handleArtifactsApi(
    new Request(`https://bithub.example/api/artifacts/repos/demo/trees/${'b'.repeat(40)}`, {
      headers,
    }),
    env,
  );
  assert.equal(tree.status, 200);
  assert.equal((await tree.json()).tree.entries[0].path, 'README.md');

  assert.deepEqual(calls, [
    { method: 'list', options: { limit: 25, cursor: undefined } },
    { method: 'get', name: 'demo' },
    { method: 'log', options: { ref: 'main', limit: 5, offset: 2 } },
    { method: 'get', name: 'demo' },
    { method: 'readCommit', hash: 'a'.repeat(40) },
    { method: 'get', name: 'demo' },
    { method: 'readTree', hash: 'b'.repeat(40) },
  ]);
});

test('artifacts browse API validates repository, hash, and pagination inputs before using the binding', async () => {
  const { binding, calls } = createArtifactsBinding();
  const env = authorizedEnv(binding);
  const headers = { authorization: 'Bearer bithub-reader-secret' };

  const invalidRepo = await handleArtifactsApi(
    new Request('https://bithub.example/api/artifacts/repos/not%2Fa%2Frepo/log', { headers }),
    env,
  );
  assert.equal(invalidRepo.status, 404);

  const invalidHash = await handleArtifactsApi(
    new Request('https://bithub.example/api/artifacts/repos/demo/commits/short', { headers }),
    env,
  );
  assert.equal(invalidHash.status, 400);

  const invalidLimit = await handleArtifactsApi(
    new Request('https://bithub.example/api/artifacts/repos/demo/log?limit=101', { headers }),
    env,
  );
  assert.equal(invalidLimit.status, 400);
  assert.deepEqual(calls, []);
});
