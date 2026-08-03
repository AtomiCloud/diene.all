import { expectGreen, expectRedBecause } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-fmt-actionlint-green',
      description: 'The treefmt actionlint member passes on the untouched workflows.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix fmt --no-write-lock-file -- --ci --formatters actionlint', 'fmt-actionlint');
      },
    },
    {
      name: 'mutation-fmt-actionlint-caught',
      description: 'A focused sabotage must turn the fmt-actionlint mechanism red.',
      kind: 'mutation',
      expectedImpact: ['workflow-actionlint'],
      async run(repo: any) {
        const path = '.github/workflows/⚡reusable-precommit.yaml';
        const original = await repo.read(path);
        try {
          await repo.patch(path, {
            find: '        run: nix develop .#ci -c ./scripts/ci/pre-commit.sh',
            replace: '        runs: nix develop .#ci -c ./scripts/ci/pre-commit.sh',
          });
          await expectRedBecause(
            repo,
            'nix fmt --no-write-lock-file -- --ci --formatters actionlint',
            'fmt-actionlint',
            [
              '.github/workflows/⚡reusable-precommit.yaml',
              'step must run script with "run" section or run action with "uses" section',
            ],
          );
        } finally {
          await repo.write(path, original);
        }
      },
    },
  ],
};
