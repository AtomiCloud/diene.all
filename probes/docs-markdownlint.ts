import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const gate = 'nix develop --no-write-lock-file .#ci -c pre-commit run a-markdownlint --all-files';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-docs-markdownlint-green',
      description: 'Markdownlint accepts the complete standards and skill-trigger payload.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'docs-markdownlint');
      },
    },
    {
      name: 'mutation-docs-markdownlint-caught',
      description: 'A second top-level heading must be refused as MD025, not merely fail.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // The fixture is any standard index this node still ships; the subject is
        // the gate, not the topic. It moved off `authorization` when that segment
        // left for the .NET layer — a mutation arm whose target no longer exists
        // lands in `broken` on the venue, and `broken` voids the whole run.
        const path = 'docs/standards/datetime/index.md';
        const original = await repo.read(path);
        try {
          await repo.write(path, `${original}\n# Duplicate datetime title\n`);
          await expectRedBecause(repo, gate, 'docs-markdownlint', [path, 'MD025/single-title/single-h1']);
        } finally {
          await repo.write(path, original);
        }
      },
    },
  ],
};
