import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<30s).
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.unit.toml tests/unit/error-classification.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-catalog-error-classification-green',
      description:
        'The Problem catalog drives the error tier: recoverable retries inline, fatal stays on the page, uncatalogued escalates.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'catalog-error-classification');
      },
    },
    {
      name: 'mutation-catalog-error-classification-caught',
      description: 'Classifying an uncatalogued Problem as recoverable turns the classification suite red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // An unknown failure offered as "try again" retries forever against a
        // backend that will never succeed, and never feeds the catalog loop.
        const path = 'src/lib/error-classification/index.ts';
        const source = await repo.read(path);
        await repo.write(
          path,
          source.replace(
            "if (entry === undefined) return { tier: 'uncatalogued' };",
            "if (entry === undefined) return { tier: 'recoverable' };",
          ),
        );
        await expectBunRed(repo, command, 'catalog-error-classification');
      },
    },
  ],
};
