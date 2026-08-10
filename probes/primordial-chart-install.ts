import { expectBunGreen } from './lib/bun-command.ts';

// Cost: heavy — brings up a throwaway k3d cluster where one is reachable.
//
// `helm template` proves the chart renders; only a real apiserver proves it
// installs. The rail degrades to render + kubeconform where no docker daemon is
// reachable, and says so loudly in its own output — see
// scripts/validate/chart-install-smoke.sh. CI's in-cluster job runs the real path.
const command = 'nix develop .#ci -c ./scripts/validate/chart-install-smoke.sh primordial';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-primordial-chart-install-green',
      description:
        'The primordial chart installs into a live cluster (or, without a reachable daemon, renders manifests that pass kubeconform — noted as degraded in the run output).',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'primordial-chart-install');
      },
    },
  ],
};
