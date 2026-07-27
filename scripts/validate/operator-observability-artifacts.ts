#!/usr/bin/env bun
// Independent oracle for the fleet-operator observability contract. It parses the
// rendered chart (not the source text) so a presence proof cannot false-green on a
// comment or a stringly match, and it fails CLOSED: every structured fact and count
// below must hold, and the dead webhook six-state taxonomy / ticks-rate liveness
// surface must be positively absent. It never substitutes a permissive absence check
// for a positive assertion.

import { execFileSync, execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const CHART = 'infra/root_chart';
const METRICS_GO = 'adapters/operator/metrics/metrics.go';
const CONDITIONS_GO = 'lib/operator/conditions/conditions.go';
const RUNTIME_GO = 'internal/operatorruntime/runtime.go';
const failures: string[] = [];
let checksRun = 0;

function fail(msg: string): void {
  failures.push(msg);
}

function check(cond: boolean, msg: string): void {
  checksRun += 1;
  if (!cond) fail(msg);
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

// Canonical metric names referenced in a PromQL expression, folded to base family
// (histogram _bucket/_count/_sum suffixes drop off). Only fleet_operator_* and
// controller_runtime_* names are tracked; framework helpers like workqueue_depth
// are out of the taxonomy's scope.
function metricRefs(text: string): string[] {
  const out = new Set<string>();
  for (const m of text.matchAll(/(?:fleet_operator|controller_runtime)_[a-z_]+/g)) {
    out.add(m[0].replace(/_(bucket|count|sum)$/, ''));
  }
  return [...out];
}

const DEAD_METRIC = 'fleet_operator_webhook_events_total';
const TICKS_RATE_METRIC = 'fleet_operator_reconcile_ticks_total';
const STALENESS_METRIC = 'fleet_operator_last_successful_tick_timestamp_seconds';
const PAGING_TYPES = ['Conflict', 'Unresolved', 'Drifted', 'BlastBrakeTripped'];
const LABEL_OTHER = 'other';

// The retired webhook delivery-path surface: the dead metric family, its
// `webhook_state` label, and the six-state vocabulary's distinctive members. Bare
// English words that legitimately occur elsewhere (`owned`, `lag`) are excluded on
// purpose — this bans the vocabulary, not the dictionary.
const RETIRED_TOKENS = [
  DEAD_METRIC,
  'webhook_events',
  'webhook_state',
  'six-state',
  'six state',
  'double-own',
  'no-owner',
  'dead-letter',
  'deadletter',
  'misroute',
];

// Files that must never silently regrow the retired surface: the rendered chart is
// checked separately, these are the owned sources and governing documents.
const RETIRED_SCAN_FILES = [
  `${CHART}/values.yaml`,
  `${CHART}/templates/grafanaalertrulegroup.yaml`,
  `${CHART}/templates/dashboard.yaml`,
  `${CHART}/templates/metric-taxonomy.yaml`,
  `${CHART}/README.md`,
  'docs/domain/operator-conventions.md',
  'observability/README.md',
  'observability/SIGNALS.md',
  'observability/overview.md',
  'observability/alerts/README.md',
  'observability/dashboards/README.md',
];

// The safe DEFAULT render: both sample controllers enabled, no configured MarkTick
// producer. Nothing here may page on an empty series.
const defaultManifests = render(['--set', 'controllers.note=true', '--set', 'controllers.journal=true']);
const docs = toDocs(defaultManifests);

// The EXPLICIT-PRODUCER render: one real controller declared as a producer of the
// last-successful-tick timestamp gauge, which is what earns a no-data page.
const TICK_PRODUCER = 'dependency';
const producerManifests = render(['--set', `alerts.tickProducerControllers[0]=${TICK_PRODUCER}`]);
const producerDocs = toDocs(producerManifests);

// Alerts are GrafanaAlertRuleGroup, never PrometheusRule.
check(
  byKind(docs, 'PrometheusRule').length === 0,
  'PrometheusRule must not be used; alerts must be GrafanaAlertRuleGroup',
);

// ---- ServiceMonitor (authn/authz-filtered scrape) --------------------------------
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

// Collected for the taxonomy/chart consistency proof at the end.
const alertExprs: string[] = [];
const dashExprs: string[] = [];

// ---- GrafanaAlertRuleGroup -------------------------------------------------------
{
  const groups = byKind(docs, 'GrafanaAlertRuleGroup');
  check(groups.length >= 1, 'expected at least one GrafanaAlertRuleGroup');
  const rules: any[] = groups.flatMap(g => g?.spec?.rules ?? []);
  check(rules.length > 0, 'GrafanaAlertRuleGroup must declare rules');

  const exprOf = (r: any): string => r?.data?.[0]?.model?.expr ?? '';
  const sourceOf = (r: any): string => r?.labels?.source ?? '';
  const findRule = (pred: (r: any) => boolean) => rules.find(pred);

  for (const r of rules) alertExprs.push(exprOf(r));

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
      sourceOf(r) === 'toy' || sourceOf(r) === 'consumer-extension',
      `rule ${uid} must be labelled source=toy|consumer-extension`,
    );
  }

  const reconcileErr = findRule(r => /controller_runtime_reconcile_errors_total/.test(exprOf(r)));
  check(!!reconcileErr && sourceOf(reconcileErr) === 'toy', 'missing toy reconcile-error-rate alert');

  const latency = findRule(r =>
    /histogram_quantile\(.*controller_runtime_reconcile_time_seconds_bucket/.test(exprOf(r)),
  );
  check(!!latency && sourceOf(latency) === 'toy', 'missing toy reconcile-latency alert');

  // SAFE DEFAULT: with no controller declared as a MarkTick producer, no staleness
  // rule may be shipped at all — an unwritten series must never page forever — and
  // nothing else in the default pack may page on no-data either.
  check(
    !rules.some(r => new RegExp(STALENESS_METRIC).test(exprOf(r))),
    'with no alerts.tickProducerControllers configured, no timestamp-staleness rule may render (an unwritten series must not page forever)',
  );
  const defaultNoDataPagers = rules.filter(r => r?.noDataState === 'Alerting').map(r => r?.uid);
  check(
    defaultNoDataPagers.length === 0,
    `no default-pack rule may page on no-data; found ${JSON.stringify(defaultNoDataPagers)}`,
  );
  check(
    !rules.some(r => new RegExp(`rate\\(${TICKS_RATE_METRIC}`).test(exprOf(r))),
    'the old ticks-rate liveness surface must be gone from the alert pack',
  );

  // Blast-brake trips page through the condition gauge: BlastBrakeTripped is in the regex.
  const conditionRules = rules.filter(r => /fleet_operator_condition\{/.test(exprOf(r)));
  check(conditionRules.length >= 1, 'missing persistent condition-state alert');
  for (const t of PAGING_TYPES) {
    check(
      conditionRules.some(r => new RegExp(t).test(exprOf(r))),
      `condition-state alert must watch ${t}`,
    );
  }
  check(
    conditionRules.some(r => /BlastBrakeTripped/.test(exprOf(r)) && sourceOf(r) === 'consumer-extension'),
    'a real (consumer-extension) controller must page on BlastBrakeTripped',
  );

  const ledger = findRule(r => /fleet_operator_ledger_failures_total/.test(exprOf(r)));
  check(!!ledger && sourceOf(ledger) === 'toy', 'missing durable-ledger-failure alert');

  const vendor = findRule(r => /fleet_operator_vendor_api_failures_total/.test(exprOf(r)));
  check(
    !!vendor && sourceOf(vendor) === 'consumer-extension',
    'missing DNS/vendor API-failure alert (consumer-extension)',
  );

  const provisioning = findRule(r =>
    /histogram_quantile\(.*fleet_operator_provisioning_duration_seconds_bucket/.test(exprOf(r)),
  );
  check(
    !!provisioning && sourceOf(provisioning) === 'consumer-extension',
    'missing provisioning-duration alert (consumer-extension)',
  );

  const compile = findRule(r => /fleet_operator_webhook_compile_failures_total/.test(exprOf(r)));
  check(!!compile && sourceOf(compile) === 'consumer-extension', 'missing webhook config-compile-failure alert');

  const ackLag = findRule(r => new RegExp('fleet_operator_materialization_ack_lag_seconds').test(exprOf(r)));
  check(!!ackLag && sourceOf(ackLag) === 'consumer-extension', 'missing webhook materialization/ack-lag alert');
  check(
    ackLag?.data?.[1]?.model?.conditions?.[0]?.evaluator?.type === 'gt',
    'ack-lag alert must fire when lag EXCEEDS the budget (gt)',
  );

  const tenantSync = findRule(r => /fleet_operator_tenant_sync_failures_total/.test(exprOf(r)));
  check(!!tenantSync && sourceOf(tenantSync) === 'consumer-extension', 'missing webhook tenant-sync-failure alert');

  // The dead six-state webhook taxonomy must be positively absent.
  check(
    !rules.some(r => new RegExp(DEAD_METRIC).test(exprOf(r))),
    `no alert may reference the dead metric ${DEAD_METRIC}`,
  );
  check(
    !rules.some(r => Object.keys(r?.labels ?? {}).some(k => /webhook.?state/i.test(k))),
    'no alert may carry a retired webhook delivery-state label',
  );
}

// ---- Timestamp-staleness alert: EXPLICIT PRODUCER case ---------------------------
// The rule must not merely be absent by default — it must appear, with its strong
// no-data paging behavior intact, exactly when a controller is declared a producer.
{
  const groups = byKind(producerDocs, 'GrafanaAlertRuleGroup');
  const rules: any[] = groups.flatMap(g => g?.spec?.rules ?? []);
  const exprOf = (r: any): string => r?.data?.[0]?.model?.expr ?? '';
  for (const r of rules) alertExprs.push(exprOf(r));

  const stale = rules.filter(r => new RegExp(STALENESS_METRIC).test(exprOf(r)));
  check(
    stale.length === 1,
    `declaring one tick producer must render exactly one timestamp-staleness rule, found ${stale.length}`,
  );
  const rule = stale[0];
  check(
    rule?.labels?.controller === TICK_PRODUCER,
    `the staleness rule must be scoped to the configured producer ${TICK_PRODUCER}`,
  );
  check(
    new RegExp(`${STALENESS_METRIC}\\{controller="${TICK_PRODUCER}"\\}`).test(exprOf(rule)),
    'the staleness rule must select only the configured producer controller',
  );
  check(/time\(\)\s*-/.test(exprOf(rule)), 'liveness alert must measure staleness as time() - last-successful-tick');
  check(!/rate\(/.test(exprOf(rule)), 'liveness alert must be timestamp staleness, never a rate over the tick counter');
  check(
    rule?.noDataState === 'Alerting',
    'liveness alert must page on no-data for a configured producer (stale = page)',
  );
  check(rule?.labels?.severity === 'critical', 'the staleness page must be critical severity');
  check(
    rule?.data?.[1]?.model?.conditions?.[0]?.evaluator?.type === 'gt',
    'liveness alert must fire when staleness EXCEEDS the budget (gt)',
  );
  check(
    Number(rule?.data?.[1]?.model?.conditions?.[0]?.evaluator?.params?.[0]) > 0,
    'the staleness budget must be a positive number of seconds',
  );
  check(
    !!rule?.annotations?.description && /producer/.test(rule.annotations.description),
    'the staleness rule must document that it pages because the controller is a configured tick producer',
  );
  const otherNoDataPagers = rules.filter(r => r?.noDataState === 'Alerting' && r !== rule).map(r => r?.uid);
  check(
    otherNoDataPagers.length === 0,
    `only the configured-producer staleness rule may page on no-data; found ${JSON.stringify(otherNoDataPagers)}`,
  );

  // A producer outside the bounded controller vocabulary would page on a series the
  // recorder can never write (it folds the name to `other`), so the render must fail.
  check(
    renderFails(['--set', 'alerts.tickProducerControllers[0]=not-a-controller']),
    'a tick producer outside the bounded controller vocabulary must fail to render',
  );
  check(
    renderFails(['--set', 'alerts.consumerControllers[0]=not-a-controller']),
    'a consumer controller outside the bounded controller vocabulary must fail to render',
  );
  check(
    renderFails(['--set', 'alerts.webhookController=not-a-controller']),
    'a webhook controller outside the bounded controller vocabulary must fail to render',
  );
  check(
    renderFails(['--set', 'metricLabels.controllers=null']),
    'an empty bounded controller vocabulary must fail to render (the guard must not become vacuous)',
  );
}

// ---- Dashboard -------------------------------------------------------------------
{
  const dashCm = docs.find(d => d?.kind === 'ConfigMap' && d?.metadata?.labels?.grafana_dashboard === '1');
  check(!!dashCm, 'missing grafana_dashboard ConfigMap');
  if (dashCm) {
    const raw = dashCm.data?.['fleet-operator.json'];
    check(!!raw, 'dashboard ConfigMap must carry fleet-operator.json');
    let dash: any;
    try {
      dash = JSON.parse(raw);
    } catch (e) {
      fail(`embedded dashboard JSON is not valid JSON: ${(e as Error).message}`);
    }
    if (dash) {
      check(typeof dash.schemaVersion === 'number', 'dashboard must declare a numeric schemaVersion');
      check(dash.uid === 'fleet-operator', 'dashboard uid must be fleet-operator');
      check(Array.isArray(dash.panels) && dash.panels.length > 0, 'dashboard must declare panels');
      const exprs: string[] = dash.panels.flatMap((p: any) => (p?.targets ?? []).map((t: any) => t?.expr ?? ''));
      for (const e of exprs) dashExprs.push(e);
      const joined = exprs.join('\n');
      for (const [label, re] of [
        ['reconcile rate', /controller_runtime_reconcile_total/],
        ['reconcile errors', /controller_runtime_reconcile_errors_total/],
        ['reconcile latency', /controller_runtime_reconcile_time_seconds_bucket/],
        ['condition state', /fleet_operator_condition/],
        ['ledger failures', /fleet_operator_ledger_failures_total/],
        ['reconcile staleness', new RegExp(`time\\(\\)\\s*-.*${STALENESS_METRIC}`)],
        ['vendor/DNS failures', /fleet_operator_vendor_api_failures_total/],
        ['provisioning duration', /fleet_operator_provisioning_duration_seconds_bucket/],
        ['webhook compile failures', /fleet_operator_webhook_compile_failures_total/],
        ['materialization/ack lag', /fleet_operator_materialization_ack_lag_seconds/],
        ['tenant-sync failures', /fleet_operator_tenant_sync_failures_total/],
        ['observe-mode plan actions', /fleet_operator_plan_actions/],
      ] as [string, RegExp][]) {
        check(re.test(joined), `dashboard missing a panel for ${label}`);
      }
      check(!new RegExp(DEAD_METRIC).test(joined), `dashboard must not reference the dead metric ${DEAD_METRIC}`);
      check(
        !new RegExp(`rate\\(${TICKS_RATE_METRIC}`).test(joined),
        'dashboard liveness must be timestamp-staleness, not a ticks rate',
      );
    }
  }
}

// ---- Metric taxonomy -------------------------------------------------------------
const EMITTED = [
  'fleet_operator_condition',
  'fleet_operator_ledger_failures_total',
  'fleet_operator_reconcile_ticks_total',
  'fleet_operator_vendor_api_failures_total',
  'fleet_operator_provisioning_duration_seconds',
  'fleet_operator_last_successful_tick_timestamp_seconds',
  'fleet_operator_webhook_compile_failures_total',
  'fleet_operator_materialization_ack_lag_seconds',
  'fleet_operator_tenant_sync_failures_total',
  'fleet_operator_plan_actions',
];
const FRAMEWORK = [
  'controller_runtime_reconcile_total',
  'controller_runtime_reconcile_errors_total',
  'controller_runtime_reconcile_time_seconds',
];
let taxonomyKnown = new Set<string>();
let taxonomyLabels: any = null;
let taxonomyPagingTypes: string[] = [];
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
      const framework: string[] = tax.framework ?? [];
      for (const m of EMITTED) check(emitted.includes(m), `taxonomy emitted missing ${m}`);
      for (const m of FRAMEWORK) check(framework.includes(m), `taxonomy framework missing ${m}`);
      taxonomyKnown = new Set<string>([...emitted, ...framework]);

      check(tax.liveness?.metric === STALENESS_METRIC, 'taxonomy liveness.metric must be the timestamp gauge');
      check(
        tax.liveness?.semantics === 'timestamp-staleness',
        'taxonomy liveness.semantics must be timestamp-staleness',
      );

      const pageTypes: string[] = tax.paging?.conditionTypes ?? [];
      taxonomyPagingTypes = pageTypes;
      for (const t of PAGING_TYPES) check(pageTypes.includes(t), `taxonomy paging.conditionTypes missing ${t}`);
      check(
        tax.paging?.conditionMetric === 'fleet_operator_condition',
        'taxonomy paging.conditionMetric must be the condition gauge',
      );

      taxonomyLabels = tax.labels ?? null;
      check(!!taxonomyLabels, 'taxonomy must declare the bounded label vocabularies under labels');
      check(
        taxonomyLabels?.other === LABEL_OTHER,
        `taxonomy labels.other must be the fixed ${LABEL_OTHER} overflow sentinel`,
      );

      // Delivery-path ownership is declared positively, not merely implied by absence.
      check(
        tax.ownership?.webhookDeliveryPath === 'mercury',
        'taxonomy must declare mercury owns the webhook delivery path',
      );
      check(
        tax.ownership?.webhookConfigPlane === 'fleet-operator',
        'taxonomy must declare the fleet-operator owns the webhook config plane',
      );

      // The dead six-state webhook taxonomy is positively absent.
      check(!emitted.includes(DEAD_METRIC), `taxonomy must not list the dead metric ${DEAD_METRIC}`);
      check(!new RegExp(DEAD_METRIC).test(rawTax), `taxonomy text must not mention ${DEAD_METRIC}`);
      check(tax.consumerExtensions?.webhook?.states === undefined, 'the dead webhook six-state block must be gone');
    }
  }
}

// ---- Taxonomy / chart consistency (fail-closed) ----------------------------------
{
  const referenced = new Set<string>([...alertExprs, ...dashExprs].flatMap(metricRefs));
  check(referenced.size >= 10, `expected the chart to reference a non-trivial metric set, saw ${referenced.size}`);
  for (const name of referenced) {
    check(taxonomyKnown.has(name), `chart references ${name} but the taxonomy does not declare it (emitted/framework)`);
  }
  // Every emitted-with-a-panel-or-alert name is the point; the taxonomy may be a superset.
  check(!referenced.has(DEAD_METRIC), `chart must not reference the dead metric ${DEAD_METRIC}`);
}

// ---- Bounded label vocabularies: chart taxonomy vs the Go recorder ---------------
// The cardinality claim is only real if the chart's documented vocabulary is the one
// the recorder actually enforces, so both are read from source and compared as sets.
// The condition vocabulary is compared by CONSTANT REFERENCE: the recorder must
// consume every pure lib/operator/conditions type rather than respell any of them.
const metricsGo = readFileSync(METRICS_GO, 'utf8');
const conditionsGo = readFileSync(CONDITIONS_GO, 'utf8');

function goMarkedVocabulary(source: string, key: string): string[] {
  const block = new RegExp(`// BEGIN taxonomy:${key}\\b([\\s\\S]*?)// END taxonomy:${key}\\b`).exec(source);
  if (!block) return [];
  return [...block[1].matchAll(/"([^"]*)"/g)].map(m => m[1]);
}

function sameSet(a: string[], b: string[]): boolean {
  const left = new Set(a);
  const right = new Set(b);
  return left.size === right.size && [...left].every(v => right.has(v));
}

{
  const goControllers = goMarkedVocabulary(metricsGo, 'controllers');
  const goVendors = goMarkedVocabulary(metricsGo, 'vendors');
  check(goControllers.length > 0, `${METRICS_GO} must declare a marked controller vocabulary block`);
  check(goVendors.length > 0, `${METRICS_GO} must declare a marked vendor vocabulary block`);
  check(
    new RegExp(`LabelOther\\s*=\\s*"${LABEL_OTHER}"`).test(metricsGo),
    `${METRICS_GO} must fix the overflow sentinel to ${LABEL_OTHER}`,
  );
  check(
    !goControllers.includes(LABEL_OTHER) && !goVendors.includes(LABEL_OTHER),
    `${LABEL_OTHER} is the overflow sentinel and must not also be a vocabulary member`,
  );

  const taxControllers: string[] = taxonomyLabels?.controllers ?? [];
  const taxVendors: string[] = taxonomyLabels?.vendors ?? [];
  const taxConditionTypes: string[] = taxonomyLabels?.conditionTypes ?? [];
  check(
    sameSet(goControllers, taxControllers),
    `taxonomy labels.controllers ${JSON.stringify(taxControllers)} must equal the recorder vocabulary ${JSON.stringify(goControllers)}`,
  );
  check(
    sameSet(goVendors, taxVendors),
    `taxonomy labels.vendors ${JSON.stringify(taxVendors)} must equal the recorder vocabulary ${JSON.stringify(goVendors)}`,
  );

  // Every controller seam the runtime can enable must have its own bounded label,
  // including a reserved seam that emits nothing yet: otherwise its first writer
  // would silently land on `other` and its series would be invisible.
  const seams = [
    ...readFileSync(RUNTIME_GO, 'utf8').matchAll(
      /flags\.BoolVar\(&config\.Enable[A-Za-z0-9]+,\s*"enable-([a-z0-9-]+)"/g,
    ),
  ].map(m => m[1]);
  check(seams.length > 0, `${RUNTIME_GO} must declare the controller enable seams (parse found none)`);
  for (const seam of seams) {
    check(
      taxControllers.includes(seam),
      `runtime seam --enable-${seam} has no bounded controller label; its first writer would fold to ${LABEL_OTHER}`,
    );
  }

  // Pure condition constants: identifier -> value.
  const pureTypes = new Map<string, string>();
  for (const m of conditionsGo.matchAll(/\b(Type[A-Za-z0-9]+)\s*=\s*"([^"]+)"/g)) pureTypes.set(m[1], m[2]);
  check(
    pureTypes.size >= 5,
    `${CONDITIONS_GO} must declare the pure condition type constants (parse found ${pureTypes.size})`,
  );

  const consumed = new Set<string>([...metricsGo.matchAll(/\bconditions\.(Type[A-Za-z0-9]+)\b/g)].map(m => m[1]));
  check(consumed.size > 0, `${METRICS_GO} must consume the pure condition constants, not respell them`);
  const phantom = [...consumed].filter(id => !pureTypes.has(id));
  check(phantom.length === 0, `${METRICS_GO} references undefined condition constants ${JSON.stringify(phantom)}`);
  const unconsumed = [...pureTypes.keys()].filter(id => !consumed.has(id));
  check(
    unconsumed.length === 0,
    `every pure condition type must be a bounded metric label value; the recorder folds ${JSON.stringify(unconsumed)} to ${LABEL_OTHER}`,
  );

  const consumedValues = [...consumed].map(id => pureTypes.get(id)!);
  check(
    sameSet(consumedValues, taxConditionTypes),
    `taxonomy labels.conditionTypes must equal the condition vocabulary the recorder consumes (${consumedValues.length} types vs ${taxConditionTypes.length})`,
  );

  // A paging condition type that is not a bounded label value could never be
  // recorded, so the condition-state page would be permanently silent.
  for (const t of taxonomyPagingTypes) {
    check(taxConditionTypes.includes(t), `paging condition type ${t} is not in the bounded conditionTypes vocabulary`);
  }

  // Every controller= selector the chart ships must be a bounded label value in BOTH
  // renders, otherwise the recorder's `other` folding makes the alert unmatchable.
  const selectorControllers = new Set<string>(
    [...`${defaultManifests}\n${producerManifests}`.matchAll(/controller="([^"]*)"/g)].map(m => m[1]),
  );
  check(selectorControllers.size > 0, 'the rendered chart must select controllers explicitly');
  for (const ctrl of selectorControllers) {
    check(
      taxControllers.includes(ctrl),
      `chart selects controller="${ctrl}" which is outside the bounded controller vocabulary`,
    );
  }
}

// ---- Retired webhook delivery-state surface stays retired ------------------------
// Absence checks here are the point of the finding, so they run over the rendered
// chart AND the owned sources/governing docs, and each scanned file is proven to
// exist first so a renamed file cannot make the ban vacuous.
{
  for (const token of RETIRED_TOKENS) {
    check(
      !defaultManifests.includes(token) && !producerManifests.includes(token),
      `the rendered chart must not carry the retired webhook delivery-state token "${token}"`,
    );
  }
  for (const file of RETIRED_SCAN_FILES) {
    let text = '';
    try {
      text = readFileSync(file, 'utf8');
    } catch {
      fail(`retired-surface scan target ${file} is missing`);
      continue;
    }
    check(text.length > 0, `retired-surface scan target ${file} is empty`);
    for (const token of RETIRED_TOKENS) {
      check(!text.includes(token), `${file} must not carry the retired webhook delivery-state token "${token}"`);
    }
  }

  // Positive counterpart: the governing docs must SAY who owns the delivery path.
  for (const file of ['docs/domain/operator-conventions.md', 'observability/SIGNALS.md']) {
    const text = readFileSync(file, 'utf8');
    check(/mercury/i.test(text), `${file} must state that mercury owns the webhook delivery path`);
    check(/delivery[- ]path/i.test(text), `${file} must describe the delivery-path ownership boundary`);
  }
  // The bounded-cardinality claim must be documented where the taxonomy is declared.
  const signals = readFileSync('observability/SIGNALS.md', 'utf8');
  check(
    new RegExp(`\`${LABEL_OTHER}\``).test(signals),
    `observability/SIGNALS.md must document the ${LABEL_OTHER} overflow sentinel`,
  );
  check(
    /tickProducerControllers/.test(signals),
    'observability/SIGNALS.md must document that the staleness page needs a configured tick producer',
  );
}

// ---- RBAC scraper ----------------------------------------------------------------
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

// ---- ServiceMonitor external-secret mode -----------------------------------------
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
  console.error(`❌ operator observability artifact proof failed (${failures.length}/${checksRun} checks):`);
  for (const f of failures) console.error(`  - ${f}`);
  process.exit(1);
}
console.log(`✅ operator observability artifacts proven (structured parse) — ${checksRun} assertions held`);
