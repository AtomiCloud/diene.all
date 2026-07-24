import { expect, test } from 'bun:test';

test('every core public entry is import-safe without browser globals', async () => {
  expect(globalThis).not.toHaveProperty('window');
  expect(globalThis).not.toHaveProperty('document');

  const modules = await Promise.all([
    import('../../src/index'),
    import('../../src/entries/module'),
    import('../../src/entries/landscape'),
    import('../../src/entries/content'),
    import('../../src/entries/theme'),
    import('../../src/entries/discovery'),
    import('../../src/entries/urlstate'),
    import('../../src/entries/persistence'),
    import('../../src/entries/loader'),
    import('../../src/entries/toast'),
    import('../../src/entries/a11y'),
  ]);

  expect(modules).toHaveLength(11);
  for (const entry of modules) {
    expect(Object.keys(entry).length).toBeGreaterThan(0);
  }
});
