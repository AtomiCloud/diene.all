import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const gate = 'nix develop --no-write-lock-file .#ci -c pre-commit run a-claude-links --all-files';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-claude-link-integrity-green',
      description: 'Every Markdown link in CLAUDE.md resolves to its local target.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'claude-link-integrity');
      },
    },
    {
      name: 'mutation-claude-link-integrity-caught',
      description: 'A corrupted shared-standard target must turn CLAUDE link validation red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const path = 'CLAUDE.md';
        const original = await repo.read(path);
        try {
          await repo.patch(path, {
            find: 'docs/standards/authorization/index.md',
            replace: 'docs/standards/authorization/missing.md',
          });
          await expectRedBecause(repo, gate, 'claude-link-integrity', [
            'docs/standards/authorization/missing.md',
            'File not found',
          ]);
        } finally {
          await repo.write(path, original);
        }
      },
    },
  ],
};
