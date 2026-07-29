import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

const CHART = 'infra/primordial_chart';

// goals/dotnet-api.md L68: primordial-chart template [smoke] — `helm template` renders the T3 CR
// SET for every values file. So this asserts the KINDS, not merely that something rendered: a
// chart that emitted only a GrafanaFolder would satisfy "resources > 0" while rendering none of
// the T3 custom resources the row is named for.
//
// The three asserted kinds are the UNCONDITIONAL members of the set. CloudflareDeploy
// (if-edge) and VirtualLandscapeService (if-serving-a-vlandscape) are conditional per L153-161,
// so requiring them would fail a CORRECT chart — over-assertion is as wrong as under-assertion.
//
// ONE dev-shell entry, looping inside it — never one `nix develop` per values file. The app
// chart's row came back `broken` for exactly that reason (PROBES §5: never cold-start a
// toolchain N times in one row).
//
// Every failure mode below exits 0 on its own, so each is asserted explicitly:
//   * `test "$n" -gt 0`  — a glob matching no files loops zero times and passes
//   * per-kind presence  — `helm template` exits 0 while rendering nothing
//   * printed totals     — the row reports WHAT it checked, not merely that it ran
const KINDS = ['PlatformDependency', 'Problem', 'LogtoApp'];

const GATE =
  `nix develop .#ci -c bash -c 'set -e; n=0; k=0; out=$(mktemp); ` +
  `trap "rm -f \\"$out\\"" EXIT; ` +
  `for v in ${CHART}/values*.yaml; do ` +
  `helm template dotnet-api-primordial ${CHART} -f "$v" > "$out"; ` +
  `c=$(grep -c "^kind:" "$out"); ` +
  `test "$c" -gt 0 || { echo "rendered 0 resources for $v"; exit 1; }; ` +
  KINDS.map(kind => `grep -q "^kind: ${kind}$" "$out" || { echo "values $v rendered NO ${kind}"; exit 1; }; `).join(
    '',
  ) +
  `n=$((n+1)); k=$((k+c)); ` +
  `done; ` +
  `test "$n" -gt 0 || { echo "no values files matched"; exit 1; }; ` +
  `echo "rendered $n values file(s), $k resource(s), each carrying ${KINDS.join(' + ')}"'`;

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-api-primordial-chart-template-green',
    description: 'The primordial chart renders the T3 CR set for every values file.',
    async run(repo: any) {
      await expectGreen(repo, GATE, 'dotnet-api-primordial-chart-template', 600000);
    },
  },
});
