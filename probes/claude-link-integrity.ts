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
          // Both strings measured from this arm's own refusal. The second one matters:
          // a sabotage that lands on the link TEXT instead of the link TARGET leaves the
          // gate green, and only the "File not found" line proves lychee was handed a
          // broken target rather than a renamed label.
          await expectRedBecause(repo, gate, 'claude-link-integrity', [
            '- hook id: a-claude-links',
            'File not found. Check if file exists and path is correct',
          ]);
        } finally {
          await repo.write(path, original);
        }
      },
    },
  ],
};
