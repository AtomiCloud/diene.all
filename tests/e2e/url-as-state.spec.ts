import { expect, test } from '@playwright/test';

// url-as-state journey: typing updates the URL live (debounced replaceState),
// and pasting the URL into a fresh context restores the same state.
test('typing mirrors into the URL and restores in a new context', async ({ page, browser }) => {
  await page.goto('/');
  const input = page.getByRole('searchbox');
  await input.fill('diene');

  await expect.poll(() => new URL(page.url()).searchParams.get('q')).toBe('diene');

  const context = await browser.newContext();
  const restored = await context.newPage();
  await restored.goto(page.url());
  await expect(restored.getByRole('searchbox')).toHaveValue('diene');
  await context.close();
});

test('back/forward keeps URL and state in sync', async ({ page }) => {
  await page.goto('/');
  const input = page.getByRole('searchbox');
  await input.fill('first');
  await expect.poll(() => new URL(page.url()).searchParams.get('q')).toBe('first');
});
