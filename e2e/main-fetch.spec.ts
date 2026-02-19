import { test, expect } from '@playwright/test';

test('cloudflare fetch entrypoint serves SSR page', async ({ page }) => {
  const response = await page.goto('/readme');

  expect(response).not.toBeNull();
  expect(response!.status()).toBe(200);
  await expect(page.getByRole('heading', { level: 1, name: 'README.md' })).toBeVisible();
  await expect(page.getByRole('heading', { level: 1, name: 'bithub' })).toBeVisible();
  await expect(page.getByRole('banner')).toContainText('bithub');
});
