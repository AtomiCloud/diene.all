import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-workflow-actionlint-green',
      description: 'Actionlint accepts every workflow independently of job-to-script validation.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c actionlint', 'workflow-actionlint');
      },
    },
    {
      name: 'mutation-workflow-actionlint-caught',
      description: 'A focused sabotage must turn the workflow-actionlint mechanism red.',
      kind: 'mutation',
      expectedImpact: ['fmt-actionlint'],
      async run(repo: any) {
        await repo.patch('.github/workflows/⚡reusable-precommit.yaml', {
          find: '        run: nix develop .#ci -c ./scripts/ci/pre-commit.sh',
          replace: '        runs: nix develop .#ci -c ./scripts/ci/pre-commit.sh',
        });
        await expectRed(repo, 'nix develop .#ci -c actionlint', 'workflow-actionlint');
      },
    },
  ],
};
