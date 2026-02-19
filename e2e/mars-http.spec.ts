import { test, expect } from '@playwright/test';

test('home route is available', async ({ page }) => {
  const response = await page.goto('/');

  expect(response).not.toBeNull();
  expect(response!.status()).toBe(200);
  await expect(page.getByRole('heading', { level: 1, name: 'bithub' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'README.md' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'files' })).toBeVisible();
});

test('healthz returns ok', async ({ request }) => {
  const response = await request.get('/healthz');

  expect(response.status()).toBe(200);
  await expect(response.text()).resolves.toBe('ok');
});

test('readme route renders markdown content', async ({ page }) => {
  const response = await page.goto('/readme');

  expect(response).not.toBeNull();
  expect(response!.status()).toBe(200);
  await expect(page.getByRole('heading', { level: 1, name: 'README.md' })).toBeVisible();
  await expect(page.getByRole('heading', { level: 1, name: 'bithub' })).toBeVisible();
});

test('readme route returns SSR html payload', async ({ request }) => {
  const response = await request.get('/readme');

  expect(response.status()).toBe(200);
  const html = await response.text();
  expect(html).toContain('<header');
  expect(html).toContain('<main');
  expect(html).toContain('<h1>README.md</h1>');
  expect(html).toContain('<h1>bithub</h1>');
});

test('readme page is readable with javascript disabled', async ({ browser, baseURL }) => {
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

test('filer route lists root entries', async ({ page }) => {
  const response = await page.goto('/filer');

  expect(response).not.toBeNull();
  expect(response!.status()).toBe(200);
  await expect(page.getByRole('heading', { level: 1, name: 'filer' })).toBeVisible();
  await expect(page.getByRole('link', { name: '[file] README.md' })).toBeVisible();
  await expect(page.getByRole('link', { name: '[dir] src/' })).toBeVisible();
});

test('file route returns content for existing file', async ({ page }) => {
  const response = await page.goto('/file?path=src/core/api_state.mbt');

  expect(response).not.toBeNull();
  expect(response!.status()).toBe(200);
  await expect(page.getByRole('heading', { level: 1, name: 'src/core/api_state.mbt' })).toBeVisible();
  await expect(page.locator('main')).toContainText('pub struct ApiState');
});

test('file route returns 404 for missing file', async ({ page }) => {
  const response = await page.goto('/file?path=missing.txt');

  expect(response).not.toBeNull();
  expect(response!.status()).toBe(404);
  await expect(page.getByRole('heading', { level: 1, name: 'missing.txt' })).toBeVisible();
  await expect(page.locator('main')).toContainText('not found');
});
