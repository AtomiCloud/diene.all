const requiredArtifacts = [
  'docs/standards/observability/alerts.md',
  'docs/standards/observability/faro.md',
  'docs/standards/observability/index.md',
  'docs/standards/observability/otel.md',
  'docs/standards/observability/primordial-chart.md',
  'docs/standards/observability/runbooks.md',
  'docs/standards/observability/signals.md',
  'docs/standards/grafana-dashboards/index.md',
  'docs/standards/grafana-dashboards/sandbox.md',
  '.claude/skills/observability-check/SKILL.md',
  '.claude/skills/observability-check/templates/SIGNALS-template.md',
  '.claude/skills/grafana-alert/SKILL.md',
  '.claude/skills/grafana-alert-set/SKILL.md',
  '.claude/skills/grafana-alert-set/templates/alert-template.yaml',
  '.claude/skills/grafana-dashboards/SKILL.md',
  '.claude/skills/grafana-runbook/SKILL.md',
  '.claude/skills/grafana-runbook/templates/overview-template.md',
  '.claude/skills/grafana-runbook/templates/runbook-template.md',
  'observability/README.md',
  'observability/SIGNALS.md',
  'observability/overview.md',
  'observability/alerts/README.md',
  'observability/dashboards/README.md',
  'probes/observability-add-back-checklist.md',
] as const;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-observability-standards-present',
      description: 'The O standards, O1 contracts, root source scaffold, five thin skills, and chain checklist exist.',
      kind: 'baseline',
      async run(repo: any) {
        for (const artifact of requiredArtifacts) {
          if ((await repo.glob(artifact)).length !== 1) {
            throw new Error(`missing observability/O1 payload artifact: ${artifact}`);
          }
        }
      },
    },
  ],
};
