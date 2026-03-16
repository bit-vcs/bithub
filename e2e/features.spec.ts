import { test, expect } from '@playwright/test';

// ---------------------------------------------------------------------------
// Code Search
// ---------------------------------------------------------------------------
test.describe('code search', () => {
  test('/search page has search form', async ({ page }) => {
    await page.goto('/search?q=');
    await expect(
      page.getByRole('heading', { name: 'Search' }),
    ).toBeVisible();
    await expect(page.locator('input[name="q"]')).toBeVisible();
  });

  test('search finds matching code', async ({ page }) => {
    await page.goto('/search?q=ApiState');
    await expect(page.getByText(/results for "ApiState"/)).toBeVisible();
    await expect(page.getByRole('listitem').first()).toBeVisible();
    // results should link to file
    await expect(
      page.getByRole('link').filter({ hasText: /\.mbt:\d+/ }).first(),
    ).toBeVisible();
  });

  test('search with no results shows 0', async ({ page }) => {
    await page.goto('/search?q=xyznonexistent123');
    await expect(page.getByText('0 results')).toBeVisible();
  });

  test('empty query shows no results section', async ({ page }) => {
    await page.goto('/search?q=');
    await expect(page.getByText(/results for/)).toHaveCount(0);
  });

  test('search result links to file page', async ({ page }) => {
    await page.goto('/search?q=mars_route_specs');
    const link = page
      .getByRole('link')
      .filter({ hasText: /core\.mbt/ })
      .first();
    await expect(link).toBeVisible();
    await link.click();
    await expect(page.locator('main')).toContainText('mars_route_specs');
  });
});

// ---------------------------------------------------------------------------
// Issues
// ---------------------------------------------------------------------------
test.describe('issues list', () => {
  test('/issues page lists seeded issues', async ({ page }) => {
    await page.goto('/issues');
    await expect(
      page.getByRole('heading', { name: 'Issues' }),
    ).toBeVisible();
    await expect(page.getByText('relay webhook')).toBeVisible();
    await expect(page.getByText('R2')).toBeVisible();
  });

  test('issue links navigate to detail', async ({ page }) => {
    await page.goto('/issues');
    await page.getByRole('link', { name: '#1' }).click();
    await expect(
      page.getByRole('heading', { name: /relay webhook/ }),
    ).toBeVisible();
  });
});

test.describe('issue detail', () => {
  test('shows issue body rendered as markdown', async ({ page }) => {
    await page.goto('/issues/1');
    await expect(
      page.getByRole('heading', { name: /#1.*relay webhook/i }),
    ).toBeVisible();
    await expect(page.getByText(/state:.*closed/)).toBeVisible();
    // body contains markdown list items
    await expect(page.getByText('Happy path')).toBeVisible();
  });

  test('shows comments', async ({ page }) => {
    await page.goto('/issues/1');
    await expect(
      page.getByRole('heading', { name: /Comments/ }),
    ).toBeVisible();
    await expect(page.getByText('ci-bot')).toBeVisible();
    await expect(page.getByText('21 test cases')).toBeVisible();
  });

  test('issue without comments shows no comments heading', async ({
    page,
  }) => {
    await page.goto('/issues/2');
    await expect(
      page.getByRole('heading', { name: /Comments/ }),
    ).toHaveCount(0);
  });

  test('nonexistent issue returns 404', async ({ page }) => {
    const res = await page.goto('/issues/999');
    expect(res!.status()).toBe(404);
    await expect(page.getByText('issue not found')).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// Activity Feed
// ---------------------------------------------------------------------------
test.describe('activity feed', () => {
  test('/activity page shows events', async ({ page }) => {
    await page.goto('/activity');
    await expect(
      page.getByRole('heading', { name: 'Activity' }),
    ).toBeVisible();
    // should have commit events from seed data
    await expect(page.getByText('commit').first()).toBeVisible();
  });

  test('activity events link to detail pages', async ({ page }) => {
    await page.goto('/activity');
    // At least one event should have a link
    const eventLinks = page.locator('table tbody a');
    await expect(eventLinks.first()).toBeVisible();
  });

  test('activity includes issue events', async ({ page }) => {
    await page.goto('/activity');
    await expect(page.getByText('issue').first()).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// Compare (Branch Diff)
// ---------------------------------------------------------------------------
test.describe('compare', () => {
  test('compare two commits shows diff', async ({ page }) => {
    // abc1234 → bbb2345 (one commit between them)
    const res = await page.goto('/compare/bbb2345...abc1234');
    expect(res!.status()).toBe(200);
    await expect(
      page.getByRole('heading', { name: /Compare/ }),
    ).toBeVisible();
    await expect(page.getByText(/1 commits/)).toBeVisible();
    await expect(page.getByText(/files changed/)).toBeVisible();
  });

  test('compare shows commit list', async ({ page }) => {
    await page.goto('/compare/bbb2345...abc1234');
    await expect(
      page.getByRole('heading', { name: 'Commits' }),
    ).toBeVisible();
    await expect(
      page.getByRole('link', { name: 'abc1234' }),
    ).toBeVisible();
  });

  test('compare shows changed files', async ({ page }) => {
    await page.goto('/compare/bbb2345...abc1234');
    await expect(
      page.getByRole('heading', { name: 'Files changed' }),
    ).toBeVisible();
    await expect(page.getByText('ci.mbt')).toBeVisible();
  });

  test('compare with invalid format returns 400', async ({ page }) => {
    const res = await page.goto('/compare/invalid');
    expect(res!.status()).toBe(400);
    await expect(page.getByText('usage:')).toBeVisible();
  });

  test('compare with nonexistent commits returns 404', async ({ page }) => {
    const res = await page.goto('/compare/xxx...yyy');
    expect(res!.status()).toBe(404);
  });

  test('multi-commit compare collects all diffs', async ({ page }) => {
    // ccc3456 → abc1234 (two commits: bbb2345, abc1234)
    const res = await page.goto('/compare/ccc3456...abc1234');
    expect(res!.status()).toBe(200);
    await expect(page.getByText(/2 commits/)).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// Navigation includes new links
// ---------------------------------------------------------------------------
test.describe('navigation', () => {
  test('nav bar includes issues, activity, search', async ({ page }) => {
    await page.goto('/');
    const nav = page.getByRole('navigation', {
      name: 'primary navigation',
    });
    await expect(nav.getByRole('link', { name: 'issues' })).toBeVisible();
    await expect(nav.getByRole('link', { name: 'activity' })).toBeVisible();
    await expect(nav.getByRole('link', { name: 'search' })).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// Markdown rendering in file view
// ---------------------------------------------------------------------------
test.describe('markdown file rendering', () => {
  test('README.md renders as HTML not raw text', async ({ page }) => {
    await page.goto('/file?path=README.md');
    // Should have rendered markdown (h1 from content), not raw # syntax
    await expect(
      page.getByRole('heading', { name: 'bithub' }),
    ).toBeVisible();
    // Should NOT show raw markdown syntax
    await expect(page.locator('main')).not.toContainText('# bithub');
  });

  test('.md files in filer link to rendered view', async ({ page }) => {
    await page.goto('/file?path=docs/notes.txt');
    // non-markdown file shows in code block
    await expect(page.locator('pre code')).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// SSR without JavaScript
// ---------------------------------------------------------------------------
test.describe('SSR without JavaScript', () => {
  test('search page renders without JS', async ({ browser, baseURL }) => {
    const ctx = await browser.newContext({
      baseURL,
      javaScriptEnabled: false,
    });
    const page = await ctx.newPage();
    await page.goto('/search?q=ApiState');
    await expect(page.getByRole('heading', { name: 'Search' })).toBeVisible();
    await expect(page.getByText(/results for/)).toBeVisible();
    await ctx.close();
  });

  test('issues page renders without JS', async ({ browser, baseURL }) => {
    const ctx = await browser.newContext({
      baseURL,
      javaScriptEnabled: false,
    });
    const page = await ctx.newPage();
    await page.goto('/issues');
    await expect(
      page.getByRole('heading', { name: 'Issues' }),
    ).toBeVisible();
    await ctx.close();
  });

  test('activity page renders without JS', async ({ browser, baseURL }) => {
    const ctx = await browser.newContext({
      baseURL,
      javaScriptEnabled: false,
    });
    const page = await ctx.newPage();
    await page.goto('/activity');
    await expect(
      page.getByRole('heading', { name: 'Activity' }),
    ).toBeVisible();
    await ctx.close();
  });
});
