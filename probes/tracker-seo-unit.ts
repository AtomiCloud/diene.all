import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<30s).
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.unit.toml tests/unit/tracker.test.ts tests/unit/seo.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-tracker-seo-unit-green',
      description:
        'The tracker envelope and the SEO metadata/JSON-LD builders emit their documented shapes from config.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'tracker-seo-unit');
      },
    },
    {
      name: 'mutation-tracker-seo-unit-caught',
      description: 'Emitting the wrong schema.org type in the organization JSON-LD turns the SEO suite red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // A Person where an Organization belongs is valid JSON-LD that search
        // engines silently mis-index — invisible without an assertion on the type.
        const path = 'src/lib/seo/index.ts';
        const source = await repo.read(path);
        await repo.write(path, source.replace(/'@type': 'Organization',/, "'@type': 'Person',"));
        await expectBunRed(repo, command, 'tracker-seo-unit');
      },
    },
  ],
};
