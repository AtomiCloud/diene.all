import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'presence-operator-observability-artifacts',
      description:
        'The operator observability chart surface is proven by structured parse, not substring grep: the exclusively-owned parser renders the chart, converts the multi-document YAML to structured objects, parses the embedded Grafana dashboard JSON and the metric-taxonomy YAML, and asserts the required structural fields, PromQL queries, alert states, and auth material. It verifies the GrafanaAlertRuleGroup (never PrometheusRule) covers reconcile errors, reconcile latency, poll-loop liveness/staleness (pages on no-data), persistent Conflict/Unresolved/Drifted condition state, durable-ledger failures, DNS/vendor API failures, provisioning duration, and the webhook six-state taxonomy (owned/double-own/no-owner/misroute/dead-letter/lag); that consumer-extension metrics stay honestly distinguished from toy-emitted metrics; that the dashboard and taxonomy carry the full set; and that every enabled ServiceMonitor mode presents a complete authorized bearer credential (chart scraper token or an external secret with nonempty name AND key) while a missing external name and a blank external key are both rejected at render time.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          "nix develop .#ci -c bash -lc 'bun run scripts/validate/operator-observability-artifacts.ts'",
          'operator-observability-artifacts',
        );
      },
    },
  ],
};
