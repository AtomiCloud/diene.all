#!/usr/bin/env bun
// Parse rendered YAML and embedded payloads so the presence proof cannot false-green on text matches.

import { execSync } from 'node:child_process';

const CHART = 'infra/root_chart';
const failures: string[] = [];

function fail(msg: string): void {
  failures.push(msg);
}

function render(extraArgs: string): string {
  return execSync(`helm template t ${CHART} ${extraArgs}`, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 32 * 1024 * 1024,
  });
}

function renderFails(extraArgs: string): boolean {
  try {
    execSync(`helm template t ${CHART} ${extraArgs}`, { stdio: 'ignore', maxBuffer: 32 * 1024 * 1024 });
    return false;
  } catch {
    return true;
  }
}

function toDocs(manifests: string): any[] {
  const json = execSync(`yq ea -o=json '[.]' -`, { input: manifests, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  const parsed = JSON.parse(json);
  return Array.isArray(parsed) ? parsed.filter(d => d != null) : [];
}

function yamlToJson(text: string): any {
  return JSON.parse(execSync(`yq -o=json -`, { input: text, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 }));
}

function byKind(docs: any[], kind: string): any[] {
  return docs.filter(d => d?.kind === kind);
}

function check(cond: boolean, msg: string): void {
  if (!cond) fail(msg);
}

const docs = toDocs(render('--set controllers.note=true --set controllers.journal=true'));

check(
  byKind(docs, 'PrometheusRule').length === 0,
  'PrometheusRule must not be used; alerts must be GrafanaAlertRuleGroup',
);

{
  const sms = byKind(docs, 'ServiceMonitor');
  check(sms.length === 1, `expected exactly one ServiceMonitor, found ${sms.length}`);
  const ep = sms[0]?.spec?.endpoints?.[0];
  check(ep?.scheme === 'https', 'ServiceMonitor endpoint must scrape over https');
  check(ep?.authorization?.type === 'Bearer', 'ServiceMonitor must present a Bearer authorization');
  check(!!ep?.authorization?.credentials?.name, 'ServiceMonitor Bearer credential name must be non-empty');
  check(!!ep?.authorization?.credentials?.key, 'ServiceMonitor Bearer credential key must be non-empty');
  check(ep?.tlsConfig != null, 'ServiceMonitor endpoint must carry a tlsConfig');
}

{
  const groups = byKind(docs, 'GrafanaAlertRuleGroup');
  check(groups.length >= 1, 'expected at least one GrafanaAlertRuleGroup');
  const rules: any[] = groups.flatMap(g => g?.spec?.rules ?? []);
  check(rules.length > 0, 'GrafanaAlertRuleGroup must declare rules');

  // Every rule is a query (A, prometheus) + threshold expression (C, __expr__).
  for (const r of rules) {
    const uid = r?.uid ?? '(no uid)';
    check(r?.condition === 'C', `rule ${uid} must reference threshold condition C`);
    const data = r?.data ?? [];
    check(Array.isArray(data) && data.length === 2, `rule ${uid} must carry query + threshold refs`);
    check(data[0]?.datasourceUid === 'prometheus', `rule ${uid} query must target the prometheus datasource`);
    check(data[1]?.model?.type === 'threshold', `rule ${uid} must carry a threshold expression`);
    check(!!data[1]?.model?.conditions?.[0]?.evaluator?.type, `rule ${uid} must carry a threshold evaluator`);
    check(
      r?.labels?.source === 'toy' || r?.labels?.source === 'consumer-extension',
      `rule ${uid} must be labelled source=toy|consumer-extension`,
    );
  }

  const exprOf = (r: any): string => r?.data?.[0]?.model?.expr ?? '';
  const findRule = (pred: (r: any) => boolean) => rules.find(pred);
  const sourceOf = (r: any): string => r?.labels?.source ?? '';

  const reconcileErr = findRule(r => /controller_runtime_reconcile_errors_total/.test(exprOf(r)));
  check(!!reconcileErr && sourceOf(reconcileErr) === 'toy', 'missing toy reconcile-error-rate alert');

  const latency = findRule(r =>
    /histogram_quantile\(.*controller_runtime_reconcile_time_seconds_bucket/.test(exprOf(r)),
  );
  check(!!latency && sourceOf(latency) === 'toy', 'missing toy reconcile-latency alert');

  const liveness = findRule(r => /operator_template_reconcile_ticks_total/.test(exprOf(r)));
  check(!!liveness, 'missing poll-loop liveness/staleness alert');
  check(liveness?.noDataState === 'Alerting', 'liveness alert must page on no-data (stale = page)');
  check(
    liveness?.data?.[1]?.model?.conditions?.[0]?.evaluator?.type === 'lt',
    'liveness alert must fire when the tick rate drops below threshold',
  );

  const condition = findRule(r => /operator_template_condition\{/.test(exprOf(r)));
  check(!!condition, 'missing persistent condition-state alert');
  check(
    /Conflict/.test(exprOf(condition)) && /Unresolved/.test(exprOf(condition)) && /Drifted/.test(exprOf(condition)),
    'condition-state alert must watch Conflict/Unresolved/Drifted',
  );

  const ledger = findRule(r => /operator_template_ledger_failures_total/.test(exprOf(r)));
  check(!!ledger && sourceOf(ledger) === 'toy', 'missing durable-ledger-failure alert');

  const vendor = findRule(r => /operator_template_vendor_api_failures_total/.test(exprOf(r)));
  check(
    !!vendor && sourceOf(vendor) === 'consumer-extension',
    'missing DNS/vendor API-failure alert (must be consumer-extension)',
  );

  const provisioning = findRule(r =>
    /histogram_quantile\(.*operator_template_provisioning_duration_seconds_bucket/.test(exprOf(r)),
  );
  check(
    !!provisioning && sourceOf(provisioning) === 'consumer-extension',
    'missing provisioning-duration alert (must be consumer-extension)',
  );

  // Only the five pathological webhook states alert; owned is the healthy sixth state.
  for (const state of ['double-own', 'no-owner', 'misroute', 'dead-letter', 'lag']) {
    const wr = rules.find(r => r?.labels?.webhook_state === state);
    check(!!wr, `missing webhook alert for state ${state}`);
    if (wr) {
      check(sourceOf(wr) === 'consumer-extension', `webhook ${state} alert must be consumer-extension`);
      check(
        new RegExp(`operator_template_webhook_events_total\\{[^}]*state="${state}"`).test(exprOf(wr)),
        `webhook ${state} alert must query state="${state}"`,
      );
      // Lag is a classified event rate, never a seconds budget.
      if (state === 'lag') {
        const ev = wr?.data?.[1]?.model?.conditions?.[0]?.evaluator;
        check(
          ev?.type === 'gt' && Number(ev?.params?.[0]) === 0,
          'webhook lag alert must fire on a nonzero event rate (gt 0), not a seconds budget',
        );
      }
    }
  }
  check(
    !rules.some(r => r?.labels?.webhook_state === 'owned'),
    'the healthy owned webhook state must not raise an alert',
  );

  const consumerMetrics =
    /(operator_template_vendor_api_failures_total|operator_template_provisioning_duration_seconds|operator_template_webhook_events_total)/;
  for (const r of rules) {
    if (consumerMetrics.test(exprOf(r))) {
      check(
        sourceOf(r) === 'consumer-extension',
        `rule ${r?.uid} references a consumer-extension metric but is not labelled consumer-extension`,
      );
    }
  }
}

{
  const dashCm = docs.find(d => d?.kind === 'ConfigMap' && d?.metadata?.labels?.grafana_dashboard === '1');
  check(!!dashCm, 'missing grafana_dashboard ConfigMap');
  if (dashCm) {
    const raw = dashCm.data?.['operator-template.json'];
    check(!!raw, 'dashboard ConfigMap must carry operator-template.json');
    let dash: any;
    try {
      dash = JSON.parse(raw);
    } catch (e) {
      fail(`embedded dashboard JSON is not valid JSON: ${(e as Error).message}`);
    }
    if (dash) {
      check(typeof dash.schemaVersion === 'number', 'dashboard must declare a numeric schemaVersion');
      check(dash.uid === 'operator-template', 'dashboard uid must be operator-template');
      check(Array.isArray(dash.panels) && dash.panels.length > 0, 'dashboard must declare panels');
      const exprs: string[] = dash.panels.flatMap((p: any) => (p?.targets ?? []).map((t: any) => t?.expr ?? ''));
      const joined = exprs.join('\n');
      for (const [label, re] of [
        ['reconcile rate', /controller_runtime_reconcile_total/],
        ['reconcile errors', /controller_runtime_reconcile_errors_total/],
        ['reconcile latency', /controller_runtime_reconcile_time_seconds_bucket/],
        ['condition state', /operator_template_condition/],
        ['ledger failures', /operator_template_ledger_failures_total/],
        ['liveness ticks', /operator_template_reconcile_ticks_total/],
        ['vendor/DNS failures', /operator_template_vendor_api_failures_total/],
        ['provisioning duration', /operator_template_provisioning_duration_seconds_bucket/],
        ['webhook events', /operator_template_webhook_events_total/],
      ] as [string, RegExp][]) {
        check(re.test(joined), `dashboard missing a panel for ${label}`);
      }
      const webhookExpr = exprs.find(e => /operator_template_webhook_events_total/.test(e)) ?? '';
      for (const state of ['owned', 'double-own', 'no-owner', 'misroute', 'dead-letter', 'lag']) {
        check(webhookExpr.includes(state), `webhook dashboard panel missing state ${state}`);
      }
    }
  }
}

{
  const taxCm = docs.find(d => d?.kind === 'ConfigMap' && /metric-taxonomy$/.test(d?.metadata?.name ?? ''));
  check(!!taxCm, 'missing metric-taxonomy ConfigMap');
  if (taxCm) {
    const rawTax = taxCm.data?.['taxonomy.yaml'];
    check(!!rawTax, 'taxonomy ConfigMap must carry taxonomy.yaml');
    let tax: any;
    try {
      tax = yamlToJson(rawTax);
    } catch (e) {
      fail(`embedded taxonomy YAML is not valid YAML: ${(e as Error).message}`);
    }
    if (tax) {
      const toy: string[] = tax.emittedByToy ?? [];
      for (const m of [
        'operator_template_condition',
        'operator_template_ledger_failures_total',
        'operator_template_reconcile_ticks_total',
      ]) {
        check(toy.includes(m), `taxonomy emittedByToy missing ${m}`);
      }
      const states: string[] = tax.consumerExtensions?.webhook?.states ?? [];
      const wantStates = ['owned', 'double-own', 'no-owner', 'misroute', 'dead-letter', 'lag'];
      check(
        wantStates.every(s => states.includes(s)) && states.length === wantStates.length,
        `taxonomy webhook states must be exactly the six-state taxonomy, got [${states.join(', ')}]`,
      );
      check(states.includes('owned'), 'taxonomy webhook states must include the healthy owned state');
      check(
        tax.consumerExtensions?.webhook?.healthyState === 'owned',
        'taxonomy must declare owned as the healthy webhook state',
      );
      check(!!tax.consumerExtensions?.provisioning?.metric, 'taxonomy must name the provisioning metric');
      check(!!tax.consumerExtensions?.vendor?.metric, 'taxonomy must name the vendor metric');
      const consumerNames = [
        tax.consumerExtensions?.provisioning?.metric,
        tax.consumerExtensions?.vendor?.metric,
        tax.consumerExtensions?.webhook?.metric,
      ].filter(Boolean);
      for (const n of consumerNames) {
        check(!toy.includes(n), `consumer-extension metric ${n} must not be claimed as toy-emitted`);
      }
    }
  }
}

{
  const clusterRoles = byKind(docs, 'ClusterRole');
  const scraper = clusterRoles.find(cr =>
    (cr?.rules ?? []).some((r: any) => (r?.nonResourceURLs ?? []).includes('/metrics')),
  );
  check(!!scraper, 'missing least-privilege metrics scraper ClusterRole (nonResourceURLs /metrics)');
  const manager = clusterRoles.find(cr => {
    const resources = (cr?.rules ?? []).flatMap((r: any) => r?.resources ?? []);
    return resources.includes('tokenreviews') && resources.includes('subjectaccessreviews');
  });
  check(!!manager, 'missing manager authn/authz review grants (tokenreviews + subjectaccessreviews)');
}

{
  const ext = toDocs(
    render('--set serviceMonitor.scraper.create=false --set serviceMonitor.scraper.externalSecret.name=prom-token'),
  );
  const sm = byKind(ext, 'ServiceMonitor')[0];
  check(
    sm?.spec?.endpoints?.[0]?.authorization?.credentials?.name === 'prom-token',
    'external-secret ServiceMonitor mode must render the external credential',
  );

  check(
    renderFails('--set serviceMonitor.scraper.create=false'),
    'an enabled ServiceMonitor with neither scraper nor external secret must fail to render',
  );
  check(
    renderFails(
      '--set serviceMonitor.scraper.create=false --set serviceMonitor.scraper.externalSecret.name=prom-token --set serviceMonitor.scraper.externalSecret.key=',
    ),
    'an external secret with a blank key must fail to render',
  );
}

if (failures.length > 0) {
  console.error('❌ operator observability artifact proof failed:');
  for (const f of failures) console.error(`  - ${f}`);
  process.exit(1);
}
console.log('✅ operator observability artifacts proven (structured parse)');
