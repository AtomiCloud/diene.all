import { expectBunGreen } from './lib/bun-command.ts';

// Cost: light (<20s) — vendor plus one render, no cluster.
//
// The vendoring step is not optional: Helm refuses to read files outside a chart
// directory, so the authoritative repository-root observability/ tree is copied in
// before any render. Templating without it renders a chart with no dashboards.
const command =
  "nix develop .#ci -c bash -lc './scripts/local/chart-vendor.sh && helm template primordial-probe infra/primordial_chart > /tmp/primordial-probe-render.yaml && test -s /tmp/primordial-probe-render.yaml'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-primordial-chart-template-green',
      description:
        'The primordial chart renders its dependency and observability custom resources from vendored sources.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'primordial-chart-template');
      },
    },
  ],
};
