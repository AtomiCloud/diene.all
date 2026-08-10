import { expect, test } from '@playwright/test';

// i18n locale journey: switching locale re-renders translated keys.
test('locale switch renders the translated key', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Welcome');

  await page.getByLabel('Switch language').selectOption('de');
  await expect(page).toHaveURL(/\/de/);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Herzlich willkommen');
});
