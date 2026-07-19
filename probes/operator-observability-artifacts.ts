import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'presence-operator-observability-artifacts',
      description:
        'The chart renders the ServiceMonitor, GrafanaAlertRuleGroup, dashboard, least-privilege metrics scraper RBAC, and the manager authn/authz review grants; the dashboard queries the emitted operator metrics; every enabled ServiceMonitor mode presents a complete authorized bearer credential (chart scraper token or an external secret with nonempty name AND key); a missing external name and a blank external key are both rejected at render time.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          "nix develop .#ci -c bash -lc '" +
            'set -e; r=$(helm template t infra/root_chart); ' +
            'echo "$r" | rg -q "kind: ServiceMonitor"; ' +
            'echo "$r" | rg -q "kind: GrafanaAlertRuleGroup"; ' +
            'echo "$r" | rg -q "grafana_dashboard"; ' +
            'echo "$r" | rg -q "operator_template_condition"; ' +
            'echo "$r" | rg -q "operator_template_ledger_failures_total"; ' +
            'echo "$r" | rg -q "nonResourceURLs"; ' +
            'echo "$r" | rg -q "tokenreviews"; ' +
            'echo "$r" | rg -q "authorization"; ' +
            // external authorized identity renders when the chart scraper is off
            'helm template t infra/root_chart --set serviceMonitor.scraper.create=false --set serviceMonitor.scraper.externalSecret.name=prom-token | rg -q "name: prom-token"; ' +
            // the unauthorized combination (no scraper, no external secret) is rejected
            '! helm template t infra/root_chart --set serviceMonitor.scraper.create=false >/dev/null 2>&1; ' +
            // an external secret with a blank credential key is also rejected
            '! helm template t infra/root_chart --set serviceMonitor.scraper.create=false --set serviceMonitor.scraper.externalSecret.name=prom-token --set serviceMonitor.scraper.externalSecret.key= >/dev/null 2>&1' +
            "'",
          'operator-observability-artifacts',
        );
      },
    },
  ],
};
