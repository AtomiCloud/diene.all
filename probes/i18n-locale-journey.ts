import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: heavy — a next build plus one Playwright slice. Locale switching is a
// routing behaviour, so only a real navigation proves it.
const command =
  'nix develop .#ci -c bash -lc \'./scripts/ci/setup.sh && export PATH="$(pwd)/node_modules/.bin:$PATH" && next build && ./scripts/local/standalone-assets.sh && (playwright install --with-deps chromium >/dev/null 2>&1 || playwright install chromium) && playwright test locale.spec.ts\'';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-i18n-locale-journey-green',
      description:
        'Switching locale navigates to the localized route and re-renders every translated key from the new catalogue.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'i18n-locale-journey');
      },
    },
    {
      name: 'mutation-i18n-locale-journey-caught',
      description: 'A locale switch that replaces the path without the locale option turns the locale journey red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // The select visibly changes and nothing else does: the router re-renders
        // the same locale, so the switcher looks broken only if something asserts
        // the rendered strings actually changed.
        const path = 'src/components/shell/LocaleSwitcher.tsx';
        const source = await repo.read(path);
        await repo.write(
          path,
          source.replace(
            'onChange={event => router.replace(pathname, { locale: event.target.value as AppLocale })}',
            'onChange={() => router.replace(pathname)}',
          ),
        );
        await expectBunRed(repo, command, 'i18n-locale-journey');
      },
    },
  ],
};
