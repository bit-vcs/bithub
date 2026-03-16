import { test, expect } from '@playwright/test';

test.describe('commits page', () => {
  test('lists commits in reverse chronological order', async ({ page }) => {
    await page.goto('/commits');
    await expect(page.getByRole('heading', { name: 'Commits' })).toBeVisible();
    const rows = page.getByRole('row');
    // header + at least 3 seed commits
    await expect(rows).toHaveCount(4);
    // first row after header should be the newest commit
    const firstDataRow = rows.nth(1);
    await expect(firstDataRow.getByRole('link')).toBeVisible();
  });

  test('commit links navigate to detail', async ({ page }) => {
    await page.goto('/commits');
    const link = page.getByRole('link', { name: 'abc1234' });
    await expect(link).toBeVisible();
    await link.click();
    await expect(page.getByRole('heading', { name: /Commit.*abc1234/ })).toBeVisible();
  });

  test('commit detail shows message, author, and diff', async ({ page }) => {
    const res = await page.goto('/commit/abc1234');
    expect(res).not.toBeNull();
    expect(res!.status()).toBe(200);
    await expect(page.getByText('relay webhook')).toBeVisible();
    await expect(page.getByText(/author:.*mizchi/)).toBeVisible();
    await expect(page.getByRole('heading', { name: /Changed files/ })).toBeVisible();
    await expect(page.getByText('src/core/ci.mbt')).toBeVisible();
    await expect(page.getByText('[added]')).toBeVisible();
  });

  test('commit detail shows parent link', async ({ page }) => {
    await page.goto('/commit/abc1234');
    const parentLink = page.getByRole('link', { name: 'bbb2345' });
    await expect(parentLink).toBeVisible();
    await parentLink.click();
    await expect(page.getByRole('heading', { name: /Commit.*bbb2345/ })).toBeVisible();
  });

  test('nonexistent commit returns 404', async ({ page }) => {
    const res = await page.goto('/commit/nonexistent');
    expect(res).not.toBeNull();
    expect(res!.status()).toBe(404);
    await expect(page.getByText('commit not found')).toBeVisible();
  });

  test('commit detail shows diff patch', async ({ page }) => {
    await page.goto('/commit/bbb2345');
    await expect(page.getByText('viewer.mbt')).toBeVisible();
    await expect(page.locator('pre code')).toBeVisible();
  });
});

test.describe('branches page', () => {
  test('lists branches with current branch first', async ({ page }) => {
    await page.goto('/branches');
    await expect(page.getByRole('heading', { name: 'Branches' })).toBeVisible();
    // first data row should be current branch (main)
    const firstRow = page.getByRole('row').nth(1);
    await expect(firstRow.getByText('* main')).toBeVisible();
  });

  test('shows all seed branches', async ({ page }) => {
    await page.goto('/branches');
    await expect(page.getByText('main')).toBeVisible();
    await expect(page.getByText('feat/ci-webhook')).toBeVisible();
    await expect(page.getByText('fix/template-literal')).toBeVisible();
  });

  test('branch SHA links to commit detail', async ({ page }) => {
    await page.goto('/branches');
    const shaLink = page.getByRole('link', { name: 'abc1234' });
    await expect(shaLink).toBeVisible();
    await shaLink.click();
    await expect(page.getByRole('heading', { name: /Commit/ })).toBeVisible();
  });
});

test.describe('commit edge cases', () => {
  test('root commit has no parent link', async ({ page }) => {
    await page.goto('/commit/ccc3456');
    await expect(page.getByRole('heading', { name: /Commit.*ccc3456/ })).toBeVisible();
    await expect(page.getByText('update dependencies')).toBeVisible();
    // root commit has empty parent, so no parent link
    const parentLinks = page.getByRole('link').filter({ hasText: /^[a-f0-9]{7}$/ });
    await expect(parentLinks).toHaveCount(0);
  });

  test('commit without diffs shows no changed files heading', async ({
    page,
  }) => {
    await page.goto('/commit/ccc3456');
    // ccc3456 has no diffs seeded
    await expect(
      page.getByRole('heading', { name: /Changed files/ }),
    ).toHaveCount(0);
  });

  test('commit detail page has correct SSR structure', async ({ request }) => {
    const res = await request.get('/commit/abc1234');
    const html = await res.text();
    expect(html).toContain('<header');
    expect(html).toContain('<main');
    expect(html).toContain('</html>');
    expect(html).toContain('abc1234');
  });

  test('commits page SSR contains table markup', async ({ request }) => {
    const res = await request.get('/commits');
    const html = await res.text();
    expect(html).toContain('<table');
    expect(html).toContain('<th');
    expect(html).toContain('SHA');
    expect(html).toContain('Message');
    expect(html).toContain('Author');
  });
});

test.describe('branch edge cases', () => {
  test('branches page SSR contains table markup', async ({ request }) => {
    const res = await request.get('/branches');
    const html = await res.text();
    expect(html).toContain('<table');
    expect(html).toContain('Branch');
    expect(html).toContain('SHA');
  });

  test('non-current branches are not prefixed with *', async ({ page }) => {
    await page.goto('/branches');
    const rows = page.getByRole('row');
    // feat/ci-webhook row should not have *
    const featRow = rows.filter({ hasText: 'feat/ci-webhook' });
    await expect(featRow).toBeVisible();
    await expect(featRow).not.toContainText('*');
  });

  test('branch count matches seed data', async ({ page }) => {
    await page.goto('/branches');
    // header + 3 branches
    await expect(page.getByRole('row')).toHaveCount(4);
  });
});

test.describe('navigation', () => {
  test('nav bar has commits and branches links', async ({ page }) => {
    await page.goto('/');
    const nav = page.getByRole('navigation', { name: 'primary navigation' });
    await expect(nav.getByRole('link', { name: 'commits' })).toBeVisible();
    await expect(nav.getByRole('link', { name: 'branches' })).toBeVisible();
  });

  test('home page has commits and branches in feature list', async ({ page }) => {
    await page.goto('/');
    const main = page.getByRole('main');
    await expect(main.getByRole('link', { name: 'commits' })).toBeVisible();
    await expect(main.getByRole('link', { name: 'branches' })).toBeVisible();
  });
});
