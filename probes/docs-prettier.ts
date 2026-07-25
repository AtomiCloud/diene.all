import { expectGreen, expectRed } from './lib/helpers.ts';

const gate =
  'nix fmt --no-write-lock-file -- docs/standards .claude/skills CLAUDE.md README.md --ci --formatters prettier';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-docs-prettier-green',
      description: 'Prettier accepts the complete standards, skill, and shared-pointer payload.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'docs-prettier');
      },
    },
    {
      name: 'mutation-docs-prettier-caught',
      description: 'Valid but misaligned skill frontmatter must turn the Prettier mechanism red.',
      kind: 'mutation',
      expectedImpact: ['fmt-prettier', 'precommit-treefmt-prettier'],
      async run(repo: any) {
        const path = '.claude/skills/authorization/SKILL.md';
        const original = await repo.read(path);
        try {
          await repo.patch(path, { find: 'name: authorization', replace: 'name:    authorization' });
          await expectRed(repo, gate, 'docs-prettier');
        } finally {
          await repo.write(path, original);
        }
      },
    },
  ],
};
