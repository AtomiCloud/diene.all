import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-helm-docs-green',
      description: 'The generated helm-docs hook finds no documentation drift.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pre-commit run a-helm-docs --all-files', 'hook-helm-docs');
      },
    },
    {
      name: 'mutation-hook-helm-docs-caught',
      description: 'A focused sabotage must turn the hook-helm-docs mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('infra/root_chart/Chart.yaml', {
          find: 'description: Helm chart for diene/dotnet-base',
          replace: 'description: Changed probe description',
        });
        await expectRed(
          repo,
          'nix develop .#ci -c pre-commit run a-helm-docs --all-files',
          'hook-helm-docs',
          240000,
          'files were modified by this hook',
        );
      },
    },
  ],
};
