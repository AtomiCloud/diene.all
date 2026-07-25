import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<30s) — seven renders, no cluster.
//
// This is the other direction from the schema gate: no value is involved at all.
// A template author adding a Certificate or an HTTPRoute directly would pass every
// values check and still break the invariant that keeps ONE chart valid across a
// Boron landscape, a loopback landscape, and a hosted vcluster.
const command = "nix develop .#ci -c bash -lc './scripts/validate/chart-ownership.sh'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-garden-app-chart-render-green',
      description:
        'Every profile renders a Deployment and a ClusterIP Service carrying the service-tree and instance labels, and no edge, DNS, or TLS object at all.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'garden-app-chart-render');
      },
    },
    {
      name: 'mutation-garden-app-chart-render-caught',
      description: 'A Certificate template added to the chart turns the render-ownership check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // Two owners of the same certificate is worse than none: the chart and
        // Garden's exposure materializer would fight over renewal.
        await repo.write(
          'infra/garden_app_chart/templates/probe-certificate.yaml',
          [
            'apiVersion: cert-manager.io/v1',
            'kind: Certificate',
            'metadata:',
            '  name: {{ include "gardenApp.resourceName" (dict "root" . "token" "cert") }}',
            'spec:',
            '  secretName: probe-tls',
            '  dnsNames:',
            '    - {{ include "gardenApp.surfaceName" . | quote }}',
            '',
          ].join('\n'),
        );
        await expectBunRed(repo, command, 'garden-app-chart-render');
      },
    },
  ],
};
