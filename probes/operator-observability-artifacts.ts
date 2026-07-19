import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'presence-operator-observability-artifacts',
      description:
        'The chart renders the ServiceMonitor, GrafanaAlertRuleGroup, dashboard, least-privilege metrics scraper RBAC, and the manager authn/authz review grants, and the dashboard queries the emitted operator metrics.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          "nix develop .#ci -c bash -lc 'r=$(helm template t infra/root_chart); " +
            'echo "$r" | rg -q "kind: ServiceMonitor" && ' +
            'echo "$r" | rg -q "kind: GrafanaAlertRuleGroup" && ' +
            'echo "$r" | rg -q "grafana_dashboard" && ' +
            'echo "$r" | rg -q "operator_template_condition" && ' +
            'echo "$r" | rg -q "operator_template_ledger_failures_total" && ' +
            'echo "$r" | rg -q "nonResourceURLs" && ' +
            'echo "$r" | rg -q "tokenreviews"\'',
          'operator-observability-artifacts',
        );
      },
    },
  ],
};
