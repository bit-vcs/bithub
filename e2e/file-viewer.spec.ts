import { test, expect } from '@playwright/test';

test('root opens README.md by default', async ({ page }) => {
  await page.goto('/');

  await expect(page.getByRole('link', { name: /\[\*\] README\.md/ })).toBeVisible();
  await expect(page.getByRole('heading', { level: 1, name: 'bithub' })).toBeVisible();
  await expect(page.locator('main')).toContainText('README.md');
  await expect(page.locator('main')).toContainText('Current Direction');
});

test('header is fixed to top', async ({ page }) => {
  await page.goto('/');

  const banner = page.getByRole('banner');
  await expect(banner).toBeVisible();

  const style = await banner.evaluate((el) => {
    const s = getComputedStyle(el);
    return { position: s.position, top: s.top };
  });
  expect(style.position).toBe('fixed');
  expect(style.top).toBe('0px');
});

test('root uses split layout for file list and preview', async ({ page }) => {
  await page.goto('/');

  const splitLayout = page.locator('.split-layout');
  await expect(splitLayout).toBeVisible();
  const sidebar = splitLayout.locator('.file-sidebar');
  await expect(sidebar).toBeVisible();
  const repoNav = page.getByRole('navigation', { name: 'repository files' });
  await expect(repoNav).toBeVisible();
  await expect(splitLayout.locator('main')).toBeVisible();

  const columnCount = await splitLayout.evaluate((el) => {
    const template = getComputedStyle(el).gridTemplateColumns.trim();
    return template.length === 0 ? 0 : template.split(/\s+/).length;
  });
  expect(columnCount).toBeGreaterThanOrEqual(2);

  const sidebarOverflowY = await sidebar.evaluate((el) => getComputedStyle(el).overflowY);
  expect(sidebarOverflowY).toBe('auto');

  const breadcrumbOverflowY = await page
    .getByRole('navigation', { name: 'Breadcrumb' })
    .evaluate((el) => getComputedStyle(el).overflowY);
  expect(breadcrumbOverflowY).not.toBe('auto');

  const heights = await splitLayout.evaluate((el) => {
    const sidebar = el.querySelector('.file-sidebar');
    return {
      layoutHeight: el.clientHeight,
      sidebarHeight: sidebar ? sidebar.clientHeight : 0,
    };
  });
  expect(heights.layoutHeight).toBeGreaterThan(0);
  expect(heights.sidebarHeight).toBeGreaterThanOrEqual(heights.layoutHeight - 2);

  const scrollState = await splitLayout.evaluate((el) => {
    const main = el.querySelector('main');
    const sidebar = el.querySelector('.file-sidebar');
    if (!(main instanceof HTMLElement) || !(sidebar instanceof HTMLElement)) {
      return null;
    }
    main.scrollTop = 240;
    const mainAfter = main.scrollTop;
    const sidebarAfterMain = sidebar.scrollTop;
    sidebar.scrollTop = 180;
    return {
      mainAfter,
      sidebarAfterMain,
      sidebarAfter: sidebar.scrollTop,
      mainAfterSidebar: main.scrollTop,
      pageScrollable: document.documentElement.scrollHeight > document.documentElement.clientHeight,
    };
  });
  expect(scrollState).not.toBeNull();
  expect(scrollState!.mainAfter).toBeGreaterThan(0);
  expect(scrollState!.sidebarAfterMain).toBe(0);
  expect(scrollState!.sidebarAfter).toBeGreaterThan(0);
  expect(scrollState!.mainAfterSidebar).toBe(scrollState!.mainAfter);
  expect(scrollState!.pageScrollable).toBeFalsy();
});

test('mobile layout switches to stacked preview-first layout', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');

  const splitLayout = page.locator('.split-layout');
  await expect(splitLayout).toBeVisible();
  const sidebar = splitLayout.locator('.file-sidebar');
  await expect(sidebar).toBeVisible();

  const nav = page.getByRole('navigation', { name: 'repository files' });
  await expect(nav).toBeVisible();

  const navPosition = await nav.evaluate((el) => getComputedStyle(el).position);
  expect(navPosition).toBe('static');

  const mainOrder = await splitLayout.locator('main').evaluate((el) => getComputedStyle(el).order);
  const sidebarOrder = await sidebar.evaluate((el) => getComputedStyle(el).order);
  expect(Number(mainOrder)).toBeLessThan(Number(sidebarOrder));
});

test('can open a source file from nav', async ({ page }) => {
  await page.goto('/');

  await page.getByRole('link', { name: 'src/cmd/bithub/main.mbt' }).click();

  await expect(page).toHaveURL(/\/blob\/src\/cmd\/bithub\/main\.mbt$/);
  await expect(page.locator('main')).toContainText('fn main');
});

test('code preview uses syntree highlight html', async ({ page }) => {
  await page.goto('/blob/src/cmd/bithub/main.mbt');

  await expect(page.locator('main pre.highlight')).toBeVisible();
  const coloredSpanCount = await page.locator('main pre.highlight code span[style*="color:"]').count();
  expect(coloredSpanCount).toBeGreaterThan(0);
});

test('path traversal is rejected', async ({ page }) => {
  const response = await page.goto('/blob/..%2FREADME.md');

  expect(response).not.toBeNull();
  expect(response!.status()).toBe(400);
  await expect(page.locator('main')).toContainText('Invalid path.');
});

test('issues list page is available', async ({ page }) => {
  await page.goto('/');

  await page.getByRole('link', { name: 'issues' }).click();

  await expect(page).toHaveURL(/\/issues$/);
  await expect(page.getByRole('heading', { level: 1, name: 'Issues' })).toBeVisible();
});

test('issues route works with query string', async ({ page }) => {
  await page.goto('/issues?state=open');

  await expect(page.getByRole('heading', { level: 1, name: 'Issues' })).toBeVisible();
});

test('blob route works with query string', async ({ page }) => {
  const response = await page.goto('/blob/README.md?raw=1');

  expect(response).not.toBeNull();
  expect(response!.status()).toBe(200);
  await expect(page.locator('main')).toContainText('README.md');
});

test('missing blob returns 404 page', async ({ page }) => {
  const response = await page.goto('/blob/not-found-file.txt');

  expect(response).not.toBeNull();
  expect(response!.status()).toBe(404);
  await expect(page.locator('main')).toContainText('File not found');
});

test('unknown route returns 404 page', async ({ page }) => {
  const response = await page.goto('/__no_such_route__');

  expect(response).not.toBeNull();
  expect(response!.status()).toBe(404);
  await expect(page.locator('main')).toContainText('Route not found.');
});

test('can navigate back to home from issues page', async ({ page }) => {
  await page.goto('/issues');
  await page.getByRole('banner').getByRole('link', { name: 'bithub' }).click();

  await expect(page).toHaveURL(/\/$/);
  await expect(page.locator('main')).toContainText('README.md');
});
