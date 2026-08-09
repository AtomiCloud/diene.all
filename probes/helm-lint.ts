import { expectGreen, expectRed, expectRedBecause } from './lib/helpers.ts';

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
        await expectRedBecause(repo, 'nix develop .#ci -c helm lint infra/root_chart', 'helm-lint', [
          "Chart.yaml: apiVersion 'invalid' is not valid",
          '1 chart(s) failed',
        ]);
      },
    },
    {
      name: 'mutation-helm-lint-values-schema-caught',
      description: "A schema-invalid value supplied through Helm's real CLI override seam turns direct lint red.",
      kind: 'mutation',
      async run(repo: any) {
        await expectRed(
          repo,
          'nix develop .#ci -c helm lint infra/root_chart --set worker.replicas=invalid',
          'helm-lint',
        );
      },
    },
  ],
};
