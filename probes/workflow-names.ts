import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-workflow-names-green',
      description: 'Every present split orchestrator uses its canonical workflow name.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c ./scripts/validate/workflows.sh workflow-names', 'workflow-names');
      },
    },
    {
      name: 'mutation-workflow-names-caught',
      description: 'A focused sabotage must turn the workflow-names mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('.github/workflows/ci.yaml', { find: 'name: CI', replace: 'name: Continuous Integration' });
        await expectRed(repo, 'nix develop .#ci -c ./scripts/validate/workflows.sh workflow-names', 'workflow-names');
      },
    },
  ],
};
