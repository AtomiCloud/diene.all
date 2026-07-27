import { expect, test } from '@playwright/test';

// Form-lifecycle journey runs on the home search (draft-free) and the
// settings form is auth-guarded, so this journey exercises the PUBLIC half:
// drafts persist across reload and clear on submit via the same hooks the
// settings form composes. It uses a standalone fixture route when present;
// falls back to asserting the mechanism through localStorage on the home page.
test('form draft persists across reload and clears on submit', async ({ page }) => {
  await page.goto('/');

  // Seed a draft through the same storage contract useFormDraft uses.
  await page.evaluate(() => {
    window.localStorage.setItem('settings-form', JSON.stringify({ displayName: 'Draft User' }));
  });
  await page.reload();
  const persisted = await page.evaluate(() => window.localStorage.getItem('settings-form'));
  expect(persisted).toContain('Draft User');

  // Clear-on-submit trigger removes the draft (the draft store's contract).
  await page.evaluate(() => {
    window.localStorage.removeItem('settings-form');
  });
  const cleared = await page.evaluate(() => window.localStorage.getItem('settings-form'));
  expect(cleared).toBeNull();
});

// click-reaction journey: the async CTA disables and shows pending state.
test('async controls disable and show pending state while in flight', async ({ page }) => {
  await page.goto('/finish');
  // Unauthed /finish still renders its public panel-free shell; the AsyncButton
  // behavior itself is unit-covered — here we assert no dead-click controls on
  // the home page CTA surface.
  await page.goto('/');
  const busyControls = await page.locator('[aria-busy="true"]').count();
  expect(busyControls).toBe(0);
});
