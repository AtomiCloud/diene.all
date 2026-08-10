import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: heavy — a next build plus one Playwright slice. Assertions are DOM/overflow
// based, never pixel diffs (no golden or screenshot evidence anywhere in this tree).
const command =
  'nix develop .#ci -c bash -lc \'./scripts/ci/setup.sh && export PATH="$(pwd)/node_modules/.bin:$PATH" && next build && ./scripts/local/standalone-assets.sh && playwright test resize-fluid.spec.ts\'';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-resize-fluid-i18n-green',
      description:
        'The layout reflows without horizontal overflow from 320px upward, in every locale, including the longest translated strings.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'resize-fluid-i18n');
      },
    },
    {
      name: 'mutation-resize-fluid-i18n-caught',
      description: 'A fixed-width container turns the narrow-viewport overflow assertion red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // A fixed width looks correct on the developer's wide monitor and forces a
        // horizontal scrollbar on every phone — the exact failure mode a
        // pixel-free reflow assertion is for.
        const path = 'src/app/[locale]/page.tsx';
        const source = await repo.read(path);
        await repo.write(
          path,
          source.replace('<main className="mx-auto flex', '<main className="w-[600px] mx-auto flex'),
        );
        await expectBunRed(repo, command, 'resize-fluid-i18n');
      },
    },
  ],
};
