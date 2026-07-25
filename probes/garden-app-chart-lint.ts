import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<15s) — one lint, no vendoring (the Garden chart embeds no
// out-of-chart sources).
const command = "nix develop .#ci -c bash -lc 'helm lint infra/garden_app_chart'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-garden-app-chart-lint-green',
      description: 'The Garden app chart passes helm lint against its default values.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'garden-app-chart-lint');
      },
    },
    {
      name: 'mutation-garden-app-chart-lint-caught',
      description: 'A chart with no name turns helm lint red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // The chart name is what every release, label, and repository index keys
        // on; a nameless chart is not installable at all.
        const path = 'infra/garden_app_chart/Chart.yaml';
        const source = await repo.read(path);
        await repo.write(path, source.replace(/^name: .*$/m, "name: ''"));
        await expectBunRed(repo, command, 'garden-app-chart-lint');
      },
    },
  ],
};
