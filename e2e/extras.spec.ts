import { test, expect } from '@playwright/test';

const WRITE_TOKEN = 'tok-write-001';
const authHeaders = { Authorization: `Bearer ${WRITE_TOKEN}` };

// ---------------------------------------------------------------------------
// File editing API
// ---------------------------------------------------------------------------
test.describe('file editing API', () => {
  test('edit file creates new version', async ({ request, page }) => {
    const res = await request.post('/api/files', {
      data: {
        path: 'docs/notes.txt',
        content: 'Updated notes content',
        message: 'Update notes',
      },
      headers: authHeaders,
    });
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.commit_sha).toBeDefined();

    // Verify file content changed
    await page.goto('/file?path=docs/notes.txt');
    await expect(page.locator('main')).toContainText('Updated notes content');
  });

  test('edit creates a commit visible in history', async ({
    request,
    page,
  }) => {
    await request.post('/api/files', {
      data: {
        path: 'test-edit.txt',
        content: 'new file via API',
        message: 'Create test file',
      },
      headers: authHeaders,
    });

    await page.goto('/commits');
    await expect(page.getByText('Create test file')).toBeVisible();
  });

  test('edit rejects without auth', async ({ request }) => {
    const res = await request.post('/api/files', {
      data: { path: 'x', content: 'y' },
    });
    expect(res.status()).toBe(401);
  });

  test('edit rejects missing path', async ({ request }) => {
    const res = await request.post('/api/files', {
      data: { content: 'y' },
      headers: authHeaders,
    });
    expect(res.status()).toBe(400);
  });
});

// ---------------------------------------------------------------------------
// Tags page
// ---------------------------------------------------------------------------
test.describe('tags', () => {
  test('/tags lists seeded tags', async ({ page }) => {
    await page.goto('/tags');
    await expect(
      page.getByRole('heading', { name: 'Tags' }),
    ).toBeVisible();
    await expect(page.getByText('v0.1.1')).toBeVisible();
    await expect(page.getByText('v0.1.0')).toBeVisible();
  });

  test('tag SHA links to commit', async ({ page }) => {
    await page.goto('/tags');
    const link = page.getByRole('link', { name: /^[a-f0-9]{7}$/ }).first();
    await expect(link).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// Stats page
// ---------------------------------------------------------------------------
test.describe('stats', () => {
  test('/stats shows repository statistics', async ({ page }) => {
    await page.goto('/stats');
    await expect(
      page.getByRole('heading', { name: 'Repository Statistics' }),
    ).toBeVisible();
    await expect(page.getByText(/Files:/)).toBeVisible();
    await expect(page.getByText(/Commits:/)).toBeVisible();
    await expect(page.getByText(/Branches:/)).toBeVisible();
  });

  test('/stats shows contributors', async ({ page }) => {
    await page.goto('/stats');
    await expect(
      page.getByRole('heading', { name: 'Contributors' }),
    ).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// RSS feed
// ---------------------------------------------------------------------------
test.describe('RSS feed', () => {
  test('/feed.xml returns valid RSS', async ({ request }) => {
    const res = await request.get('/feed.xml');
    expect(res.status()).toBe(200);
    const text = await res.text();
    expect(text).toContain('<?xml');
    expect(text).toContain('<rss');
    expect(text).toContain('<channel>');
    expect(text).toContain('<item>');
  });

  test('/feed.xml has correct content type', async ({ request }) => {
    const res = await request.get('/feed.xml');
    expect(res.headers()['content-type']).toContain('rss+xml');
  });
});

// ---------------------------------------------------------------------------
// Diff syntax highlighting
// ---------------------------------------------------------------------------
test.describe('diff highlighting', () => {
  test('commit detail has diff color classes', async ({ request }) => {
    const res = await request.get('/commit/bbb2345');
    const html = await res.text();
    // The patch for bbb2345 has - and + lines
    expect(html).toContain('diff-add');
    expect(html).toContain('diff-del');
  });
});

// ---------------------------------------------------------------------------
// PR review comments
// ---------------------------------------------------------------------------
test.describe('PR review comments', () => {
  test('add comment to PR', async ({ request, page }) => {
    // Create PR
    const createRes = await request.post('/api/pulls', {
      data: { title: 'Comment test PR', base: 'x', head: 'y' },
      headers: authHeaders,
    });
    const prId = (await createRes.json()).id;

    // Add comment
    const res = await request.post(`/api/pulls/${prId}/comments`, {
      data: { body: 'LGTM! Ship it.' },
      headers: authHeaders,
    });
    expect(res.status()).toBe(200);
    expect((await res.json()).ok).toBe(true);

    // Verify on detail page
    await page.goto(`/pulls/${prId}`);
    await expect(page.getByText('LGTM! Ship it.')).toBeVisible();
    await expect(
      page.getByRole('heading', { name: /Comments/ }),
    ).toBeVisible();
  });

  test('comment on nonexistent PR fails', async ({ request }) => {
    const res = await request.post('/api/pulls/99999/comments', {
      data: { body: 'orphan' },
      headers: authHeaders,
    });
    expect((await res.json()).ok).toBe(false);
  });
});
