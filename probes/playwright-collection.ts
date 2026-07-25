import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: heavy — a next build plus a two-spec Playwright slice (the fast slice, not
// the whole suite: this row proves the browser RAIL runs and catches a regression,
// while the individual journeys are their own rows).
const command =
  'nix develop .#ci -c bash -lc \'./scripts/ci/setup.sh && export PATH="$(pwd)/node_modules/.bin:$PATH" && next build && ./scripts/local/standalone-assets.sh && (playwright install --with-deps chromium >/dev/null 2>&1 || playwright install chromium) && playwright test well-known.spec.ts locale.spec.ts\'';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-playwright-collection-green',
      description: 'The Playwright rail boots the real standalone server and runs its specs green against it.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'playwright-collection');
      },
    },
    {
      name: 'mutation-playwright-collection-caught',
      description: 'An untranslated literal heading turns the browser collection red.',
      kind: 'mutation',
      expectedImpact: ['i18n-locale-journey'],
      async run(repo: any) {
        // A hardcoded heading renders correctly in English and silently stops
        // translating: it is exactly the regression a browser rail exists to catch
        // and a typecheck cannot.
        const path = 'src/app/[locale]/page.tsx';
        const source = await repo.read(path);
        await repo.write(path, source.replace("{t('title')}", 'Dashboard'));
        await expectBunRed(repo, command, 'playwright-collection');
      },
    },
  ],
};
