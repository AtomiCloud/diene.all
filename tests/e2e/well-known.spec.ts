import { expect, test } from '@playwright/test';

// Deeplink well-known documents served and schema-valid.
test('AASA document validates', async ({ request }) => {
  const response = await request.get('/.well-known/apple-app-site-association');
  expect(response.ok()).toBe(true);
  const body = await response.json();
  expect(Array.isArray(body.applinks.details)).toBe(true);
  expect(body.applinks.details[0].appIDs.length).toBeGreaterThan(0);
});

test('assetlinks document validates', async ({ request }) => {
  const response = await request.get('/.well-known/assetlinks.json');
  expect(response.ok()).toBe(true);
  const body = await response.json();
  expect(body[0].relation).toContain('delegate_permission/common.handle_all_urls');
  expect(body[0].target.namespace).toBe('android_app');
});

// SSR landscape payload: the server-rendered HTML carries the landscape-fed
// config (server tells client — no client detection).
test('SSR injects the landscape payload', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByLabel('system')).toContainText('nextjs-frontend');
});
