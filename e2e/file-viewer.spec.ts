import { test, expect } from '@playwright/test';

test('root opens README.md by default', async ({ page }) => {
  await page.goto('/');

  await expect(page.getByRole('link', { name: /\[\*\] README\.md/ })).toBeVisible();
  await expect(page.getByRole('heading', { level: 1, name: 'bithub' })).toBeVisible();
  await expect(page.locator('main')).toContainText('README.md');
});

test('can open a source file from nav', async ({ page }) => {
  await page.goto('/');

  await page.getByRole('link', { name: 'src/cmd/bithub/main.mbt' }).click();

  await expect(page).toHaveURL(/\/blob\/src\/cmd\/bithub\/main\.mbt$/);
  await expect(page.locator('main')).toContainText('fn main');
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
