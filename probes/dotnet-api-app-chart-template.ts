import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

const CHART = 'infra/root_chart';

// ONE dev-shell entry, looping inside it — not one `nix develop` per values file.
//
// The first version invoked `nix develop .#ci -c helm template ...` once per file, six times
// over, and the row came back `broken` while the schema row — which loops inside a SINGLE
// shell — passed cleanly on the same venue. PROBES §5 states the rule directly: pre-warm
// once, not per row; never let a row cold-start a toolchain N times.
//
// Three assertions live INSIDE the gate, because each failure mode exits 0 on its own:
//   * `test "$n" -gt 0`   — a glob matching no files would loop zero times and pass
//   * per-file kind count — `helm template` exits 0 while rendering nothing
//   * printed totals      — so the row reports WHAT it checked, not merely that it ran
const GATE =
  `nix develop .#ci -c bash -c 'set -e; n=0; k=0; ` +
  `for v in ${CHART}/values*.yaml; do ` +
  `c=$(helm template dotnet-api ${CHART} -f "$v" | grep -c "^kind:"); ` +
  `test "$c" -gt 0 || { echo "rendered 0 resources for $v"; exit 1; }; ` +
  `n=$((n+1)); k=$((k+c)); ` +
  `done; ` +
  `test "$n" -gt 0 || { echo "no values files matched"; exit 1; }; ` +
  `echo "rendered $n values file(s), $k resource(s) total"'`;

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-api-app-chart-template-green',
    description: 'The app chart renders runtime resources for every values file.',
    async run(repo: any) {
      await expectGreen(repo, GATE, 'dotnet-api-app-chart-template', 600000);
    },
  },
});
