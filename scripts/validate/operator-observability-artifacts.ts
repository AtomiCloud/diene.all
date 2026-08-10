#!/usr/bin/env bun
// Parse rendered YAML and embedded payloads so the presence proof cannot false-green on text matches.

import { execFileSync, execSync } from 'node:child_process';

const CHART = 'infra/root_chart';
const failures: string[] = [];

function fail(msg: string): void {
  failures.push(msg);
}

function render(extraArgs: string[]): string {
  return execFileSync('helm', ['template', 't', CHART, ...extraArgs], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 32 * 1024 * 1024,
  });
}

function renderFails(extraArgs: string[]): boolean {
  try {
    execFileSync('helm', ['template', 't', CHART, ...extraArgs], { stdio: 'ignore', maxBuffer: 32 * 1024 * 1024 });
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

const docs = toDocs(render([]));

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
    check(r?.labels?.source === 'boron', `rule ${uid} must be labelled source=boron`);
  }

  const exprOf = (r: any): string => r?.data?.[0]?.model?.expr ?? '';
  const findRule = (pred: (r: any) => boolean) => rules.find(pred);

  // Per-controller generic reconcile alerts for all three boron controllers.
  for (const ctrl of ['account', 'tunnel', 'exposure']) {
    const errs = findRule(r => new RegExp(`reconcile_errors_total\\{controller="${ctrl}"`).test(exprOf(r)));
    check(!!errs, `missing ${ctrl} reconcile-error-rate alert`);

    const latency = findRule(r =>
      new RegExp(`histogram_quantile\\(.*reconcile_time_seconds_bucket\\{controller="${ctrl}"`).test(exprOf(r)),
    );
    check(!!latency, `missing ${ctrl} reconcile-latency alert`);

    const liveness = findRule(r => new RegExp(`boron_reconcile_ticks_total\\{controller="${ctrl}"`).test(exprOf(r)));
    check(!!liveness, `missing ${ctrl} poll-loop liveness/staleness alert`);
    check(liveness?.noDataState === 'Alerting', `${ctrl} liveness alert must page on no-data (stale = page)`);
    check(
      liveness?.data?.[1]?.model?.conditions?.[0]?.evaluator?.type === 'lt',
      `${ctrl} liveness alert must fire when the tick rate drops below threshold`,
    );

    const provider = findRule(r => new RegExp(`boron_provider_failures_total\\{controller="${ctrl}"`).test(exprOf(r)));
    check(!!provider, `missing ${ctrl} cloudflare provider-failure alert`);
  }

  // Persistent bad condition-state alerts.
  const tokenInvalid = findRule(r =>
    /boron_condition\{controller="account",type=~"Ready\|TokenValid"\}/.test(exprOf(r)),
  );
  check(!!tokenInvalid, 'missing account token-invalid condition alert');
  const tunnelDegraded = findRule(r => /boron_condition\{controller="tunnel",type="AccountNotReady"\}/.test(exprOf(r)));
  check(!!tunnelDegraded, 'missing tunnel degraded condition alert');
  const conflicted = findRule(r => /boron_condition\{controller="exposure",type="Conflicted"\}/.test(exprOf(r)));
  check(!!conflicted, 'missing exposure conflicted condition alert');
}

{
  const dashCm = docs.find(d => d?.kind === 'ConfigMap' && d?.metadata?.labels?.grafana_dashboard === '1');
  check(!!dashCm, 'missing grafana_dashboard ConfigMap');
  if (dashCm) {
    const raw = dashCm.data?.['boron.json'];
    check(!!raw, 'dashboard ConfigMap must carry boron.json');
    let dash: any;
    try {
      dash = JSON.parse(raw);
    } catch (e) {
      fail(`embedded dashboard JSON is not valid JSON: ${(e as Error).message}`);
    }
    if (dash) {
      check(typeof dash.schemaVersion === 'number', 'dashboard must declare a numeric schemaVersion');
      check(dash.uid === 'boron', 'dashboard uid must be boron');
      check(Array.isArray(dash.panels) && dash.panels.length > 0, 'dashboard must declare panels');
      const exprs: string[] = dash.panels.flatMap((p: any) => (p?.targets ?? []).map((t: any) => t?.expr ?? ''));
      const joined = exprs.join('\n');
      for (const [label, re] of [
        ['reconcile rate', /controller_runtime_reconcile_total/],
        ['reconcile errors', /controller_runtime_reconcile_errors_total/],
        ['reconcile latency', /controller_runtime_reconcile_time_seconds_bucket/],
        ['condition state', /boron_condition/],
        ['provider failures', /boron_provider_failures_total/],
        ['liveness ticks', /boron_reconcile_ticks_total/],
      ] as [string, RegExp][]) {
        check(re.test(joined), `dashboard missing a panel for ${label}`);
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
      const emitted: string[] = tax.emitted ?? [];
      for (const m of ['boron_condition', 'boron_provider_failures_total', 'boron_reconcile_ticks_total']) {
        check(emitted.includes(m), `taxonomy emitted missing ${m}`);
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
    render([
      '--set',
      'serviceMonitor.scraper.create=false',
      '--set',
      'serviceMonitor.scraper.externalSecret.name=prom-token',
    ]),
  );
  const sm = byKind(ext, 'ServiceMonitor')[0];
  check(
    sm?.spec?.endpoints?.[0]?.authorization?.credentials?.name === 'prom-token',
    'external-secret ServiceMonitor mode must render the external credential',
  );

  check(
    renderFails(['--set', 'serviceMonitor.scraper.create=false']),
    'an enabled ServiceMonitor with neither scraper nor external secret must fail to render',
  );
  check(
    renderFails([
      '--set',
      'serviceMonitor.scraper.create=false',
      '--set',
      'serviceMonitor.scraper.externalSecret.name=prom-token',
      '--set',
      'serviceMonitor.scraper.externalSecret.key=',
    ]),
    'an external secret with a blank key must fail to render',
  );
}

if (failures.length > 0) {
  console.error('❌ operator observability artifact proof failed:');
  for (const f of failures) console.error(`  - ${f}`);
  process.exit(1);
}
console.log('✅ operator observability artifacts proven (structured parse)');
