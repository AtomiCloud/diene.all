// COST CLASS: heavy (k3d cluster + CRD fixtures + two helm installs). Justified:
// only a real API server can ADMIT a custom resource against its CRD's OpenAPI
// schema. `helm template` renders text a cluster would reject, and this row is the
// only place the T3 CR set is validated against the actual CRDs.
//
// Per PROBES §3, k3d install is ALWAYS proven-only.
//
// Unique per-invocation cluster name (PROBES §5 addendum); independently invoked
// from the app-chart row and asserting its OWN release plus its OWN admitted CRs.
import { runChartInstall } from './lib/chart-install.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-primordial-chart-install-green',
      description:
        'The primordial chart installs into the same local k3d cluster and its T3 custom resources are admitted.',
      kind: 'baseline',
      async run(repo: any) {
        await runChartInstall(repo, 'primordial-chart-install', [
          'deployed releases',
          'T3 custom resources admitted',
          'platformdependency',
        ]);
      },
    },
  ],
};
