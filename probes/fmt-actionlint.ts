import { expectGreen, expectRed } from './lib/helpers.ts';

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
        await repo.patch('.github/workflows/⚡reusable-precommit.yaml', {
          find: '        run: nix develop .#ci -c ./scripts/ci/pre-commit.sh',
          replace: '        runs: nix develop .#ci -c ./scripts/ci/pre-commit.sh',
        });
        await expectRed(repo, 'nix fmt --no-write-lock-file -- --ci --formatters actionlint', 'fmt-actionlint');
      },
    },
  ],
};
