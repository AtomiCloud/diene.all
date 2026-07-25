import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-app-chart-lint-green',
      description: 'Helm lint accepts the bun-consumer app chart through its direct invocation.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c helm lint infra/root_chart', 'app-chart-lint');
      },
    },
    {
      name: 'mutation-app-chart-lint-caught',
      description: 'Invalid chart metadata turns app-chart lint red.',
      kind: 'mutation',
      expectedImpact: ['app-chart-template'],
      async run(repo: any) {
        await repo.patch('infra/root_chart/Chart.yaml', { find: 'apiVersion: v2', replace: 'apiVersion: invalid' });
        await expectRed(repo, 'nix develop .#ci -c helm lint infra/root_chart', 'app-chart-lint');
      },
    },
  ],
};
