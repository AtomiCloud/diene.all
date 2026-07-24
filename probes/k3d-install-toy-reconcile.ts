import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-k3d-install-toy-reconcile-green',
      description:
        'The k3d harness installs the chart, proves manager health/readiness, and converges both Note and Journal (local-only, Docker).',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c ./scripts/local/operator-e2e.sh', 'k3d-install-toy-reconcile');
      },
    },
  ],
};
