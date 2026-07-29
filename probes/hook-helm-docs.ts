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
        const source = await repo.read('infra/root_chart/Chart.yaml');
        const match = source.match(/^description: .+$/m);
        if (!match) {
          throw new Error('no structural chart description found in infra/root_chart/Chart.yaml');
        }
        await repo.write(
          'infra/root_chart/Chart.yaml',
          source.replace(match[0], 'description: Changed probe description'),
        );
        await expectRed(repo, 'nix develop .#ci -c pre-commit run a-helm-docs --all-files', 'hook-helm-docs');
      },
    },
  ],
};
