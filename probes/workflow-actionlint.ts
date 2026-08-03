import { expectGreen, expectRedBecause } from './lib/helpers.ts';

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
        const path = '.github/workflows/⚡reusable-precommit.yaml';
        const original = await repo.read(path);
        try {
          await repo.patch(path, {
            find: '        run: nix develop .#ci -c ./scripts/ci/pre-commit.sh',
            replace: '        runs: nix develop .#ci -c ./scripts/ci/pre-commit.sh',
          });
          await expectRedBecause(repo, 'nix develop .#ci -c actionlint', 'workflow-actionlint', [
            '.github/workflows/⚡reusable-precommit.yaml',
            'step must run script with "run" section or run action with "uses" section',
          ]);
        } finally {
          await repo.write(path, original);
        }
      },
    },
  ],
};
