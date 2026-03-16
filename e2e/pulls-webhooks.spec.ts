import { test, expect } from '@playwright/test';

const WRITE_TOKEN = 'tok-write-001';
const authHeaders = { Authorization: `Bearer ${WRITE_TOKEN}` };

// ---------------------------------------------------------------------------
// Pull Requests
// ---------------------------------------------------------------------------
test.describe.serial('pull request lifecycle', () => {
  let prId: string;

  test('create PR via API', async ({ request }) => {
    const res = await request.post('/api/pulls', {
      data: {
        title: 'Add new feature',
        body: 'This PR adds a cool feature',
        base: 'ccc3456',
        head: 'abc1234',
      },
      headers: authHeaders,
    });
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.id).toBeDefined();
    prId = body.id;
  });

  test('PR appears in list', async ({ page }) => {
    await page.goto('/pulls');
    await expect(page.getByRole('heading', { name: 'Pull Requests' })).toBeVisible();
    await expect(page.getByText('Add new feature')).toBeVisible();
    await expect(page.getByText('open')).toBeVisible();
  });

  test('PR detail shows description and diff', async ({ page }) => {
    await page.goto(`/pulls/${prId}`);
    await expect(page.getByRole('heading', { name: /Add new feature/ })).toBeVisible();
    await expect(page.getByText('cool feature')).toBeVisible();
    await expect(page.getByText(/files changed/)).toBeVisible();
  });

  test('merge PR', async ({ request, page }) => {
    const res = await request.post(`/api/pulls/${prId}/merge`, {
      headers: authHeaders,
    });
    expect(res.status()).toBe(200);
    expect((await res.json()).ok).toBe(true);

    await page.goto(`/pulls/${prId}`);
    await expect(page.getByText(/state:.*merged/)).toBeVisible();
  });

  test('merged PR shows in list', async ({ page }) => {
    await page.goto('/pulls');
    const row = page.getByRole('row').filter({ hasText: 'Add new feature' });
    await expect(row.getByText('merged')).toBeVisible();
  });
});

test.describe('PR validation', () => {
  test('create PR rejects missing title', async ({ request }) => {
    const res = await request.post('/api/pulls', {
      data: { base: 'x', head: 'y' },
      headers: authHeaders,
    });
    expect(res.status()).toBe(400);
  });

  test('create PR rejects missing base', async ({ request }) => {
    const res = await request.post('/api/pulls', {
      data: { title: 'x', head: 'y' },
      headers: authHeaders,
    });
    expect(res.status()).toBe(400);
  });

  test('create PR rejects without auth', async ({ request }) => {
    const res = await request.post('/api/pulls', {
      data: { title: 'x', base: 'a', head: 'b' },
    });
    expect(res.status()).toBe(401);
  });

  test('nonexistent PR returns 404', async ({ page }) => {
    const res = await page.goto('/pulls/99999');
    expect(res!.status()).toBe(404);
  });

  test('close PR', async ({ request }) => {
    // Create then close
    const createRes = await request.post('/api/pulls', {
      data: { title: 'To close', base: 'x', head: 'y' },
      headers: authHeaders,
    });
    const id = (await createRes.json()).id;

    const res = await request.post(`/api/pulls/${id}/close`, {
      headers: authHeaders,
    });
    expect(res.status()).toBe(200);
    expect((await res.json()).ok).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Issue state change
// ---------------------------------------------------------------------------
test.describe('issue state change', () => {
  test('close an open issue', async ({ request, page }) => {
    // Create issue
    const createRes = await request.post('/api/issues', {
      data: { title: 'State change test' },
      headers: authHeaders,
    });
    const issueId = (await createRes.json()).id;

    // Close it
    const res = await request.post(`/api/issues/${issueId}/state`, {
      data: { state: 'closed' },
      headers: authHeaders,
    });
    expect(res.status()).toBe(200);
    expect((await res.json()).ok).toBe(true);

    // Verify on detail page
    await page.goto(`/issues/${issueId}`);
    await expect(page.getByText(/state:.*closed/)).toBeVisible();
  });

  test('reopen a closed issue', async ({ request }) => {
    const createRes = await request.post('/api/issues', {
      data: { title: 'Reopen test' },
      headers: authHeaders,
    });
    const issueId = (await createRes.json()).id;

    await request.post(`/api/issues/${issueId}/state`, {
      data: { state: 'closed' },
      headers: authHeaders,
    });

    const res = await request.post(`/api/issues/${issueId}/state`, {
      data: { state: 'open' },
      headers: authHeaders,
    });
    expect(res.status()).toBe(200);
    expect((await res.json()).ok).toBe(true);
  });

  test('state change rejects without auth', async ({ request }) => {
    const res = await request.post('/api/issues/1/state', {
      data: { state: 'closed' },
    });
    expect(res.status()).toBe(401);
  });
});

// ---------------------------------------------------------------------------
// Webhook log
// ---------------------------------------------------------------------------
test.describe('webhook log', () => {
  test('webhook log page exists', async ({ page }) => {
    await page.goto('/webhooks');
    await expect(page.getByRole('heading', { name: 'Webhook Log' })).toBeVisible();
  });

  test('webhook appears in log after trigger', async ({ request, page }) => {
    const eventId = `wh-log-${Date.now()}`;
    await request.post('/api/webhook/relay', {
      data: {
        event_type: 'relay.incoming_ref',
        event_id: eventId,
        ref: 'refs/relay/incoming/main',
        source: 'log-test',
        occurred_at: Math.floor(Date.now() / 1000),
        room: 'main',
        target: 'session:test',
      },
      headers: authHeaders,
    });

    await page.goto('/webhooks');
    const row = page.getByRole('row').filter({ hasText: eventId });
    await expect(row).toBeVisible();
    await expect(row.getByText('log-test')).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------------
test('nav includes pulls link', async ({ page }) => {
  await page.goto('/');
  const nav = page.getByRole('navigation', { name: 'primary navigation' });
  await expect(nav.getByRole('link', { name: 'pulls' })).toBeVisible();
});
