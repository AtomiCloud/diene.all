import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-primordial-chart-template-green',
      description: 'Helm template renders the primordial T3 CR set.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await repo.exec(
          'nix develop .#ci -c helm template bunconsumer-primordial infra/primordial_chart',
          {
            timeoutMs: 240000,
          },
        );
        if (result.exitCode !== 0) {
          throw new Error(`primordial-chart-template failed on the healthy repo: ${result.stderr || result.stdout}`);
        }
        if (!result.stdout.includes('kind: PlatformDependency')) {
          throw new Error('primordial-chart-template rendered no PlatformDependency union CR');
        }
      },
    },
  ],
};
