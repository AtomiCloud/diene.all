import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<20s) — vendoring plus one lint.
const command = "nix develop .#ci -c bash -lc './scripts/local/chart-vendor.sh && helm lint infra/primordial_chart'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-primordial-chart-lint-green',
      description: 'The primordial chart passes helm lint with its observability sources vendored in.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'primordial-chart-lint');
      },
    },
    {
      name: 'mutation-primordial-chart-lint-caught',
      description: 'A chart with no version turns helm lint red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // An unversioned chart cannot be packaged or promoted, so this is the
        // cheapest total break of the chart's own metadata contract.
        const path = 'infra/primordial_chart/Chart.yaml';
        const source = await repo.read(path);
        await repo.write(path, source.replace(/^version: .*$/m, "version: ''"));
        await expectBunRed(repo, command, 'primordial-chart-lint');
      },
    },
  ],
};
