import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'presence-operator-observability-artifacts',
      description: 'The ServiceMonitor, GrafanaAlertRuleGroup, and Grafana dashboard render from the chart.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci -c bash -lc \'r=$(helm template t infra/root_chart); echo "$r" | rg -q "kind: ServiceMonitor" && echo "$r" | rg -q "kind: GrafanaAlertRuleGroup" && echo "$r" | rg -q "grafana_dashboard"\'',
          'operator-observability-artifacts',
        );
      },
    },
  ],
};
