import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-app-chart-template-green',
      description: 'Helm template renders the worker Deployment and the db-init pre-sync Job.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await repo.exec('nix develop .#ci -c helm template bunconsumer infra/root_chart', {
          timeoutMs: 240000,
        });
        if (result.exitCode !== 0) {
          throw new Error(`app-chart-template failed on the healthy repo: ${result.stderr || result.stdout}`);
        }
        if (!result.stdout.includes('kind: Deployment')) {
          throw new Error('app-chart-template rendered no worker Deployment');
        }
        if (!result.stdout.includes('kind: Job') || !result.stdout.includes('argocd.argoproj.io/hook: PreSync')) {
          throw new Error('app-chart-template rendered no PreSync db-init Job');
        }
      },
    },
  ],
};
