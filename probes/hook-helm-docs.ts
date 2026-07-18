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
        const path = 'infra/root_chart/Chart.yaml';
        const source = await repo.read(path);
        const description = source.match(/^description: .+$/m)?.[0];
        if (!description) {
          throw new Error('chart description target not found');
        }
        await repo.write(path, source.replace(description, 'description: Changed probe description'));
        await expectRed(repo, 'nix develop .#ci -c pre-commit run a-helm-docs --all-files', 'hook-helm-docs');
      },
    },
  ],
};
