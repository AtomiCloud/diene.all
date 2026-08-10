import { expectBunGreen } from './lib/bun-command.ts';

// Cost: heavy — brings up a throwaway k3d cluster where one is reachable.
//
// The Garden chart's whole claim is that it installs a Deployment plus a
// ClusterIP Service and nothing else. Templating can show the object set; only an
// install shows the Service actually routes, which is what the smoke's in-cluster
// HTTP probe asserts. Degrades to render + kubeconform where no docker daemon is
// reachable — see scripts/validate/chart-install-smoke.sh.
const command = 'nix develop .#ci -c ./scripts/validate/chart-install-smoke.sh garden';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-garden-app-chart-install-green',
      description:
        'The Garden app chart installs and its ClusterIP Service answers from inside the cluster (or, without a reachable daemon, every profile renders manifests that pass kubeconform — noted as degraded).',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'garden-app-chart-install');
      },
    },
  ],
};
