import { expect, test } from '@playwright/test';

// resize-fluid under i18n (Q-D6 re-expression: NON-PIXEL DOM assertions only —
// no goldens, no screenshots): the longest-locale strings at the narrowest
// viewport must not overflow horizontally.
const NARROW = { width: 320, height: 720 };

for (const locale of ['', '/de']) {
  test(`no horizontal overflow at 320px for locale "${locale || 'en'}"`, async ({ page }) => {
    await page.setViewportSize(NARROW);
    await page.goto(`${locale}/`);
    await page.waitForLoadState('networkidle');

    const overflow = await page.evaluate(() => {
      const root = document.documentElement;
      return {
        scrollWidth: root.scrollWidth,
        clientWidth: root.clientWidth,
      };
    });
    expect(overflow.scrollWidth).toBeLessThanOrEqual(overflow.clientWidth);
  });
}
