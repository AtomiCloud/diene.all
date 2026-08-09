import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-primordial-chart-lint-green',
      description: 'Helm lint accepts the primordial chart independently of the app chart.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c helm lint infra/primordial_chart', 'primordial-chart-lint');
      },
    },
    {
      name: 'mutation-primordial-chart-lint-caught',
      description: 'Invalid primordial chart metadata turns its lint red.',
      kind: 'mutation',
      expectedImpact: ['primordial-chart-template'],
      async run(repo: any) {
        await repo.patch('infra/primordial_chart/Chart.yaml', {
          find: 'apiVersion: v2',
          replace: 'apiVersion: invalid',
        });
        await expectRed(repo, 'nix develop .#ci -c helm lint infra/primordial_chart', 'primordial-chart-lint');
      },
    },
  ],
};
