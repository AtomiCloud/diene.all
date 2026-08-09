import { expectGreen, expectRedBecause } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-workflow-names-green',
      description: 'The split orchestrators are named exactly CI and CD.',
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
        await expectRedBecause(
          repo,
          'nix develop .#ci -c ./scripts/validate/workflows.sh workflow-names',
          'workflow-names',
          ['ci.yaml workflow name must be CI'],
        );
      },
    },
  ],
};
