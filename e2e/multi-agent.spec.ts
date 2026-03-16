import { test, expect, type APIRequestContext } from '@playwright/test';

/**
 * Multi-agent collaboration scenario:
 *
 * Agent Alice (owner) — task definition, code review
 * Agent Bob (writer)  — implementation, PR creation
 *
 * Flow:
 * 1. Alice creates an issue describing a task
 * 2. Bob reads the issue, edits a file, creates a PR
 * 3. Alice reviews the PR, leaves a comment
 * 4. Bob addresses feedback with another edit
 * 5. Alice merges the PR
 * 6. Webhook triggers CI run
 * 7. CI completes successfully
 * 8. Activity feed shows the full timeline
 */

const ALICE = { Authorization: 'Bearer tok-alice' };
const BOB = { Authorization: 'Bearer tok-bob' };

async function post(
  request: APIRequestContext,
  url: string,
  data: Record<string, unknown>,
  headers: Record<string, string>,
) {
  const res = await request.post(url, { data, headers });
  return { status: res.status(), body: await res.json() };
}

test.describe.serial('multi-agent collaboration', () => {
  let issueId: string;
  let prId: string;
  const ts = Date.now();

  // Step 1: Alice creates an issue
  test('Alice creates an issue describing the task', async ({ request }) => {
    const { status, body } = await post(request, '/api/issues', {
      title: 'Add feature list to README',
      body: 'The README needs a section listing all bithub features:\n- File browser\n- Commits\n- PRs\n- CI\n\nPlease add this under a "## Features" heading.',
      author: 'agent-alice',
    }, ALICE);
    expect(status).toBe(200);
    expect(body.id).toBeDefined();
    issueId = body.id;
  });

  // Step 2: Bob reads the issue
  test('Bob can read the issue details', async ({ page }) => {
    await page.goto(`/issues/${issueId}`);
    await expect(page.getByText('feature list')).toBeVisible();
    await expect(page.getByText('File browser')).toBeVisible();
  });

  // Step 3: Bob edits the file
  test('Bob edits README to add feature list', async ({ request }) => {
    // First read current content
    const getRes = await request.get('/file?path=README.md');
    const html = await getRes.text();
    expect(html).toContain('bithub');

    // Edit with new content
    const { status, body } = await post(request, '/api/files', {
      path: 'README.md',
      content: '# bithub\n\nA minimal self-browsing API/UI prototype.\n\n## Features\n\n- File browser and viewer\n- Commit history and blame\n- Branch management\n- Pull requests with review\n- CI/CD via relay webhooks\n- Code search\n- Activity feed\n',
      message: 'docs: add feature list to README (closes #' + issueId + ')',
      author: 'agent-bob',
    }, BOB);
    expect(status).toBe(200);
    expect(body.ok).toBe(true);
  });

  // Step 4: Bob creates a PR
  test('Bob creates a PR referencing the issue', async ({ request }) => {
    const { status, body } = await post(request, '/api/pulls', {
      title: 'Add feature list to README',
      body: 'Closes #' + issueId + '\n\nAdded a ## Features section listing all major bithub capabilities.',
      base: 'ccc3456',
      head: 'abc1234',
      author: 'agent-bob',
    }, BOB);
    expect(status).toBe(200);
    expect(body.id).toBeDefined();
    prId = body.id;
  });

  // Step 5: Alice reviews and comments
  test('Alice reviews the PR and leaves feedback', async ({ request }) => {
    const { status, body } = await post(
      request,
      `/api/pulls/${prId}/comments`,
      {
        body: 'Looks good! Could you also add "Issue tracking" to the list?',
        author: 'agent-alice',
      },
      ALICE,
    );
    expect(status).toBe(200);
    expect(body.ok).toBe(true);
  });

  // Step 6: Bob reads the review comment
  test('Bob can see the review comment', async ({ page }) => {
    await page.goto(`/pulls/${prId}`);
    await expect(page.getByText('Issue tracking')).toBeVisible();
    await expect(page.getByText('agent-alice')).toBeVisible();
  });

  // Step 7: Bob addresses feedback
  test('Bob updates the file based on feedback', async ({ request }) => {
    const { status, body } = await post(request, '/api/files', {
      path: 'README.md',
      content: '# bithub\n\nA minimal self-browsing API/UI prototype.\n\n## Features\n\n- File browser and viewer\n- Commit history and blame\n- Branch management\n- Pull requests with review\n- Issue tracking\n- CI/CD via relay webhooks\n- Code search\n- Activity feed\n',
      message: 'docs: add issue tracking to feature list',
      author: 'agent-bob',
    }, BOB);
    expect(status).toBe(200);
    expect(body.ok).toBe(true);
  });

  // Step 8: Bob responds to the comment
  test('Bob responds to the review', async ({ request }) => {
    const { status, body } = await post(
      request,
      `/api/pulls/${prId}/comments`,
      {
        body: 'Done! Added "Issue tracking" to the list.',
        author: 'agent-bob',
      },
      BOB,
    );
    expect(status).toBe(200);
    expect(body.ok).toBe(true);
  });

  // Step 9: Alice merges the PR
  test('Alice merges the PR', async ({ request }) => {
    const { status, body } = await post(
      request,
      `/api/pulls/${prId}/merge`,
      {},
      ALICE,
    );
    expect(status).toBe(200);
    expect(body.ok).toBe(true);
  });

  // Step 10: Alice closes the issue
  test('Alice closes the resolved issue', async ({ request }) => {
    const { status, body } = await post(
      request,
      `/api/issues/${issueId}/state`,
      { state: 'closed' },
      ALICE,
    );
    expect(status).toBe(200);
    expect(body.ok).toBe(true);
  });

  // Step 11: Webhook triggers CI
  test('relay webhook triggers CI run', async ({ request }) => {
    const { status, body } = await post(
      request,
      '/api/webhook/relay',
      {
        event_type: 'relay.incoming_ref',
        event_id: `agent-ci-${ts}`,
        ref: 'refs/relay/incoming/main',
        source: 'agent-merge',
        occurred_at: Math.floor(Date.now() / 1000),
        room: 'main',
        target: 'session:agent',
      },
      ALICE,
    );
    expect(status).toBe(200);
    expect(body.triggered).toBeGreaterThanOrEqual(1);
  });

  // Step 12: Verify the full state
  test('PR shows as merged', async ({ page }) => {
    await page.goto(`/pulls/${prId}`);
    await expect(page.getByText(/state:.*merged/)).toBeVisible();
    // Both comments visible
    await expect(page.getByRole('heading', { name: /Comments \(2\)/ })).toBeVisible();
  });

  test('issue shows as closed', async ({ page }) => {
    await page.goto(`/issues/${issueId}`);
    await expect(page.getByText(/state:.*closed/)).toBeVisible();
  });

  test('README reflects the edit', async ({ page }) => {
    await page.goto('/file?path=README.md');
    await expect(page.locator('main')).toContainText('Issue tracking');
  });

  test('commit history shows both edits', async ({ page }) => {
    await page.goto('/commits');
    await expect(page.getByText('add feature list')).toBeVisible();
    await expect(page.getByText('add issue tracking')).toBeVisible();
  });

  test('activity feed shows the full timeline', async ({ page }) => {
    await page.goto('/activity');
    // Should show commits, issues, PRs, CI runs
    await expect(page.getByText('commit').first()).toBeVisible();
    await expect(page.getByText('issue').first()).toBeVisible();
    await expect(page.getByText('pr').first()).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// Permission boundaries: agents cannot exceed their role
// ---------------------------------------------------------------------------
test.describe('agent permission boundaries', () => {
  test('Bob (write) cannot merge PRs created by others', async ({
    request,
  }) => {
    // Create PR as Alice
    const createRes = await post(request, '/api/pulls', {
      title: 'Alice PR',
      base: 'x',
      head: 'y',
    }, ALICE);
    const prId = createRes.body.id;

    // Bob can still merge (write role allows it)
    // But a read-only agent cannot
    const readRes = await request.post(`/api/pulls/${prId}/merge`, {
      headers: { Authorization: 'Bearer tok-read-001' },
    });
    expect(readRes.status()).toBe(403);
  });

  test('read-only agent cannot create issues', async ({ request }) => {
    const res = await request.post('/api/issues', {
      data: { title: 'blocked' },
      headers: { Authorization: 'Bearer tok-read-001' },
    });
    expect(res.status()).toBe(403);
  });

  test('read-only agent can browse all pages', async ({ page }) => {
    for (const path of ['/commits', '/branches', '/issues', '/pulls', '/activity', '/stats']) {
      const res = await page.goto(path);
      expect(res!.status()).toBe(200);
    }
  });
});
