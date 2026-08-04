import { expectGreen } from './lib/helpers.ts';
import { expectRedFor } from './docs-markdownlint.ts';

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
        const path = '.claude/skills/authorization/SKILL.md';
        const original = await repo.read(path);
        try {
          await repo.patch(path, { find: 'name: authorization', replace: 'name:    authorization' });
          await expectRedFor(repo, gate, 'docs-prettier', path, 'unexpected changes detected');
        } finally {
          // treefmt rewrites in place even under --ci, so the restore is load-bearing.
          await repo.write(path, original);
        }
      },
    },
  ],
};
