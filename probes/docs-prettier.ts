import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const gate =
  'nix fmt --no-write-lock-file -- docs/standards .claude/skills CLAUDE.md README.md --ci --formatters prettier --excludes ".claude/skills/vendor/**"';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-docs-prettier-green',
      description: 'Prettier accepts the complete standards, skill, and index-pointer payload.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'docs-prettier');
      },
    },
    {
      name: 'mutation-docs-prettier-caught',
      description: 'Misaligned skill frontmatter must be refused as an unformatted file, not merely fail.',
      kind: 'mutation',
      expectedImpact: ['fmt-prettier', 'precommit-treefmt-prettier'],
      async run(repo: any) {
        // The fixture is any thin trigger this node still ships; the subject is
        // the gate, not the topic. It moved off `authorization` when that segment
        // left for the .NET layer — a mutation arm whose target no longer exists
        // lands in `broken` on the venue, and `broken` voids the whole run.
        const path = '.claude/skills/datetime/SKILL.md';
        const original = await repo.read(path);
        try {
          await repo.patch(path, { find: 'name: datetime', replace: 'name:    datetime' });
          await expectRedBecause(repo, gate, 'docs-prettier', [path, 'unexpected changes detected']);
        } finally {
          // treefmt rewrites in place even under --ci, so the restore is load-bearing.
          await repo.write(path, original);
        }
      },
    },
  ],
};
