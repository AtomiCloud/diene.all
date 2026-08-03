import { expectGreen, expectRedBecause } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-helm-lint-green',
      description: 'The generated Helm lint hook passes the root chart.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pre-commit run a-helm-lint --all-files', 'hook-helm-lint');
      },
    },
    {
      name: 'mutation-hook-helm-lint-caught',
      description: 'A focused sabotage must turn the hook-helm-lint mechanism red.',
      kind: 'mutation',
      expectedImpact: ['helm-lint'],
      async run(repo: any) {
        await repo.patch('infra/root_chart/Chart.yaml', { find: 'apiVersion: v2', replace: 'apiVersion: invalid' });
        await expectRedBecause(repo, 'nix develop .#ci -c pre-commit run a-helm-lint --all-files', 'hook-helm-lint', [
          "apiVersion 'invalid' is not valid",
        ]);
      },
    },
  ],
};
