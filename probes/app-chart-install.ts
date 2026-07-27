// COST CLASS: heavy (k3d cluster + image pull + two helm installs). Justified:
// install is the only check that proves every manifest is ADMITTED by a real API
// server, that the db-init PreSync hook Job actually COMPLETES, and that the worker
// Deployment reaches Ready. `helm template` cannot admit a manifest and `kubeconform`
// cannot run a Job, so no lighter proxy proves this mechanism.
//
// Per PROBES §3, k3d install is ALWAYS proven-only — it never becomes the caught
// proof for a chart, even when it is the only live check.
//
// The cluster name is UNIQUE per invocation (PROBES §5 addendum) and every
// kubectl/helm call is pinned to that cluster's own context.
//
// This row and primordial-chart-install both bring up their own cluster and install
// BOTH charts into it — the goal's DoD is "both install into one local cluster" —
// but they remain independently invoked mechanisms: each asserts its OWN release and
// its OWN rendered evidence and fails on its own.
import { runChartInstall } from './lib/chart-install.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-app-chart-install-green',
      description:
        'The app chart installs into a uniquely named local k3d cluster; the worker becomes Ready and the db-init PreSync hook completes.',
      kind: 'baseline',
      async run(repo: any) {
        await runChartInstall(repo, 'app-chart-install', [
          'deployed releases',
          'worker readyReplicas 1',
          'db-init hook Job succeeded 1',
        ]);
      },
    },
  ],
};
