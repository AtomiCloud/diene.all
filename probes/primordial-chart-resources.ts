// Cost: light (<5s) — a glob sweep, no shell.
//
// The chart root is checked here as STRUCTURE; whether it lints, renders, and
// installs is proven by its own gate and smoke rows. What this row adds is that
// each declared resource has a template behind it and that the observability
// sources the chart vendors at build time actually exist to be vendored.
const requiredArtifacts = [
  'infra/primordial_chart/Chart.yaml',
  'infra/primordial_chart/values.yaml',
  'infra/primordial_chart/values.schema.json',
  'infra/primordial_chart/README.md',
  'infra/primordial_chart/templates/_helpers.tpl',
  'infra/primordial_chart/templates/platformdependency.yaml',
  'infra/primordial_chart/templates/logtoapp.yaml',
  'infra/primordial_chart/templates/grafana-folder.yaml',
  'infra/primordial_chart/templates/grafana-dashboards.yaml',
  'infra/primordial_chart/templates/grafana-alerts.yaml',
  // The authoritative sources the chart COPIES in at build time. Helm cannot read
  // files outside a chart directory, so their absence is a silently empty chart
  // rather than a failed render.
  'observability/dashboards/README.md',
  'observability/alerts/README.md',
  'scripts/local/chart-vendor.sh',
] as const;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-primordial-chart-resources',
      description:
        'The primordial chart root, its schema, every dependency and observability template, and the vendoring sources exist.',
      kind: 'baseline',
      async run(repo: any) {
        for (const artifact of requiredArtifacts) {
          if ((await repo.glob(artifact)).length !== 1) {
            throw new Error(`missing primordial chart artifact: ${artifact}`);
          }
        }
      },
    },
  ],
};
