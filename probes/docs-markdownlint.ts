import { expectGreen, expectRed } from './lib/helpers.ts';

const gate = 'nix develop --no-write-lock-file .#ci -c pre-commit run a-markdownlint --all-files';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-docs-markdownlint-green',
      description: 'Markdownlint accepts the complete shared documentation payload.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'docs-markdownlint');
      },
    },
    {
      name: 'mutation-docs-markdownlint-caught',
      description: 'A second top-level heading must turn the Markdownlint mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const path = 'docs/standards/authorization/index.md';
        const original = await repo.read(path);
        try {
          await repo.write(path, `${original}\n# Duplicate authorization title\n`);
          await expectRed(repo, gate, 'docs-markdownlint');
        } finally {
          await repo.write(path, original);
        }
      },
    },
  ],
};
