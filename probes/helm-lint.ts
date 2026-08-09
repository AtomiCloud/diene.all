import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-helm-lint-green',
      description: 'Helm lint accepts the root chart through its direct invocation.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c helm lint infra/root_chart', 'helm-lint');
      },
    },
    {
      name: 'mutation-helm-lint-caught',
      description: 'A focused sabotage must turn the helm-lint mechanism red.',
      kind: 'mutation',
      expectedImpact: ['hook-helm-lint'],
      async run(repo: any) {
        await repo.patch('infra/root_chart/Chart.yaml', { find: 'apiVersion: v2', replace: 'apiVersion: invalid' });
        await expectRed(repo, 'nix develop .#ci -c helm lint infra/root_chart', 'helm-lint');
      },
    },
  ],
};
