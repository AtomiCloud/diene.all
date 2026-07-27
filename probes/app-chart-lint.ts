import { expectGreen, expectRed } from './lib/helpers.ts';

const command =
  'nix develop .#ci -c helm lint infra/root_chart --values infra/root_chart/values.lapras.yaml --values infra/root_chart/values.example.yaml';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-app-chart-lint-green',
      description: 'Helm lint accepts the bun-consumer app chart through its direct invocation.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, command, 'app-chart-lint');
      },
    },
    {
      name: 'mutation-app-chart-lint-caught',
      description: 'An invalid value in the real illustrative caller overlay turns app-chart lint red.',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('infra/root_chart/values.example.yaml', {
          find: '  replicas: 2',
          replace: '  replicas: invalid',
        });
        await expectRed(repo, command, 'app-chart-lint');
      },
    },
  ],
};
