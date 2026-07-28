// COST CLASS: heavy (k3d cluster + image pull + two helm installs). Justified:
// the goal's DoD is that BOTH charts install into ONE local cluster, and nothing
// short of a real cluster admits a T3 CR set or runs a PreSync hook.
//
// Per PROBES §3, k3d install is ALWAYS proven-only — it never becomes the caught
// arm of a gate, because a cluster that fails to come up is indistinguishable
// from a chart that fails to install.
//
// The cluster name is UNIQUE per invocation (PROBES §5 addendum) and every
// kubectl/helm call is pinned to that cluster's own context.
//
// THIS IS ONE JOINT CONTROL, RUN ONCE, AND IT REPLACES THE TWO SEPARATE
// app-chart-install / primordial-chart-install BASELINES.
//
// Why they were merged (gloria, 2026-07-28; defect found in C2-charts r1,
// characterised by yanira, direction endorsed by noel #390):
//
//   The two probes each called the SAME chart-install script, which installs
//   app THEN primordial from the SAME sandbox tree. Each invocation created its
//   own k3d cluster, so RUNTIME isolation was genuinely real — but INPUT
//   isolation was absent, because both read the charts off one mutated tree.
//
//   So a metadata sabotage aimed at either chart reddened BOTH installs:
//     - app-chart-lint mutates root_chart `type`  -> poisons primordial AT THE APP STEP
//     - primordial-chart-lint mutates primordial_chart `version` -> poisons app AT THE PRIMORDIAL STEP
//   Observed as `control_failed` on the OTHER probe's baseline in C2-charts r1.
//
//   SEPARATE INVOCATION AND CLUSTER DOES NOT ESTABLISH SEPARATE MECHANISM SCOPE.
//   Two probes each claimed independence they did not have.
//
// Why NOT scope each install to only its own chart: that would make the probes
// independent but would STOP TESTING THE STATED REQUIREMENT. The DoD is "both
// install into one local cluster". If the requirement is joint, the mechanism is
// joint, and one control must assert it.
import { runChartInstall } from './lib/chart-install.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-chart-install-green',
      description:
        'Both charts install into ONE uniquely named local k3d cluster: the worker becomes Ready, the db-init PreSync hook completes, and the primordial T3 custom resources are admitted.',
      kind: 'baseline',
      async run(repo: any) {
        await runChartInstall(repo, 'chart-install', [
          'deployed releases',
          'worker readyReplicas 1',
          'db-init hook Job succeeded 1',
          'T3 custom resources admitted',
          'platformdependency',
        ]);
      },
    },
  ],
};
