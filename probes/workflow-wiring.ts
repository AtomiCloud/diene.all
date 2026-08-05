import { expectGreen, expectRedBecause } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-workflow-wiring-green',
      description: 'Every orchestrator job resolves through a reusable workflow to an existing CI script.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c dlint ci-wiring', 'workflow-wiring');
      },
    },
    {
      name: 'mutation-workflow-wiring-caught',
      description: 'A focused sabotage must turn the workflow-wiring mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('.github/workflows/⚡reusable-precommit.yaml', {
          find: './scripts/ci/pre-commit.sh',
          replace: './scripts/ci/missing.sh',
        });
        await expectRedBecause(repo, 'nix develop .#ci -c dlint ci-wiring', 'workflow-wiring', [
          "workflow references missing script 'scripts/ci/missing.sh'",
        ]);
      },
    },
  ],
};
