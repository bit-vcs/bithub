import { test, expect } from '@playwright/test';

test('cloudflare fetch entrypoint serves SSR page', async ({ page }) => {
  const response = await page.goto('/readme');

  expect(response).not.toBeNull();
  expect(response!.status()).toBe(200);
  await expect(page.getByRole('heading', { level: 1, name: 'README.md' })).toBeVisible();
  await expect(page.getByRole('heading', { level: 1, name: 'bithub' })).toBeVisible();
  await expect(page.getByRole('banner')).toContainText('bithub');
});

test('cloudflare fetch readme route returns SSR html payload', async ({ request }) => {
  const response = await request.get('/readme');

  expect(response.status()).toBe(200);
  const html = await response.text();
  expect(html).toContain('<header');
  expect(html).toContain('<main');
  expect(html).toContain('<h1>README.md</h1>');
  expect(html).toContain('<h1>bithub</h1>');
});

test('cloudflare fetch route works with javascript disabled', async ({ browser, baseURL }) => {
  const context = await browser.newContext({
    baseURL,
    javaScriptEnabled: false,
  });
  const page = await context.newPage();

  const response = await page.goto('/readme');
  expect(response).not.toBeNull();
  expect(response!.status()).toBe(200);
  await expect(page.getByRole('heading', { level: 1, name: 'README.md' })).toBeVisible();
  await expect(page.getByRole('main')).toContainText('bithub');

  await context.close();
});
