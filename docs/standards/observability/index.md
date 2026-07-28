# Observability Standards

How AtomiCloud instruments, visualizes, alerts, and responds. This is the umbrella article; the authoritative detail lives in the sub-pages:

| Page                                                 | Covers                                                                                                              |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| [Signal Decisions](./signals.md)                     | The six-gate decision cascade, signal **cost** (active series, log volume, trace sampling), the `SIGNALS.md` record |
| [Alerts](./alerts.md)                                | The rule contract, all seven alert types with worked examples, set/portfolio design, validation                     |
| [Runbooks](./runbooks.md)                            | Runbook structure, triage flowchart/table, style rules                                                              |
| [Grafana Dashboards](../grafana-dashboards/index.md) | Two-tier dashboard model, authoring rules, sandbox self-verification                                                |
| [OpenTelemetry Alignment](./otel.md)                 | The canonical config block, resource identity, library ownership, lifecycle, and evidence boundary                  |
| [Faro Frontend Variant](./faro.md)                   | Shared Next.js/Flutter initialization contract and consumer-owned module scaffolds                                  |
| [Primordial-Chart Rendering](./primordial-chart.md)  | Root-source vendoring and Grafana Operator CR rendering in each service's primordial chart                          |

Five skills trigger these standards, in order:

```
observability-check   →  decide WHICH signals a feature needs (default: none)
grafana-dashboards    →  visualize signals (two-tier model)
grafana-alert-set     →  design the service's alert portfolio
grafana-alert         →  write one well-formed alert rule
grafana-runbook       →  write the service runbook covering the alert set
```

---

## Contract 1: the label model — declared once, stamped everywhere

Every metric, log line, trace, alert, and dashboard carries the service-tree labels — but **nobody hand-writes them per signal**. They are declared once and stamped mechanically:

| Label                             | Meaning                                                       | Declared where                                      |
| --------------------------------- | ------------------------------------------------------------- | --------------------------------------------------- |
| `landscape`                       | Environment (our env equivalent)                              | Per install — chart values                          |
| `platform` / `service` / `module` | Position in the service tree (LPSM)                           | Once per service — chart values                     |
| `severity`                        | Urgency of the _condition_: `critical` \| `warning` \| `info` | **The only label an alert author writes**, per rule |

LPSM is **built in — never authored**. Alert and dashboard definitions are pure Grafana-domain objects (no Kubernetes, no labels beyond what the filename implies); the service's primordial-chart transformer merges the LPSM labels, per the [Transformation Contract](./alerts.md#the-transformation-contract). Definitions stay context-free and portable: the same definition serves every landscape, and routing decides what to do with each fired instance.

**How stamping works.** The standard specifies the mapping implemented by the reusable primordial-chart helper: it reads each tier file (a flat YAML dict — the one-file-per-tier layout means there are no arrays to manipulate), derives severity + emoji from the filename, and merges the service-tree labels into the rule it emits. In Helm this is one native dict merge (`mergeOverwrite (dict "severity" (base $path | trimSuffix ".yaml")) $.Values.serviceTree`) plus fill-in-the-blanks templating — and `required`/`fail` calls make `helm template` refuse to render on structural violations. Result per rule:

```yaml
# transformed output (sketch)
- uid: webhook-retry-queue-critical # derived: <slug>-<severity(filename)>
  title: 🚨 Webhook retry queue saturated # derived: emoji prefix from filename
  # …condition/data plumbing per the contract…
  labels:
    severity: critical # from the FILENAME
    landscape: raichu # ┐
    platform: tracker # │ merged in from the deployment context
    service: zinc # │
    module: webhook # ┘
```

This stamps **alert** labels. LPSM on metrics/logs/traces comes from the telemetry pipeline: the deployment puts the service-tree values on the workload (pod labels / OTel resource attributes), and the platform's collection relabels them onto every sample at ingest — two halves, one values source.

**Rules never encode paging or environment logic** — what actually notifies whom is decided centrally by the platform's routing configuration, from the labels alerts already carry. The same rule fires in every landscape; the router decides what to do with it.

## Contract 2: folder layout — flat, primordial-chart-synced

This repo is one service. Its dashboards and alerts ship as Kubernetes CRs from its primordial chart. The source of truth lives flat at the repo root; the chart build copies it into a gitignored generated directory inside `infra/primordial_chart/` (Helm cannot read files outside the chart directory, and out-of-chart symlinks are rejected):

```text
.
└── observability/                # SOURCE OF TRUTH (the repo IS the service)
    ├── SIGNALS.md                # decision record — see Signal Decisions
    ├── overview.md               # shared system context — see Runbooks
    ├── dashboards/               # curated dashboards (only if custom metrics earn them)
    │   └── overview.json         #   uid <platform>-<service>-overview; more files for deep-dives
    └── alerts/
        └── <alert-slug>/         # ONE ALERT SET = ONE FOLDER
            ├── critical.yaml     # one file per tier — the FILENAME is the severity
            ├── warning.yaml      #   (info.yaml for a third tier; delete unused tiers)
            └── runbook.md        # THE runbook for this alert
```

- **Deployment is fixed by R20** — the folder is pure Grafana-domain source; the service's own **primordial chart** turns it into Grafana Operator resources on Primordial using the reusable helm-wrapper helper. The app chart remains pure runtime. A central many-repository observability chart and ad hoc CI/kustomize renderers are not conforming deployment homes.
- **The chart copy is generated** — `observability/` remains authoritative. The copy inside `infra/primordial_chart/` is gitignored, rebuilt before lint/template/package/publish, and never hand-edited or committed. See [Primordial-Chart Rendering](./primordial-chart.md).
- **Grafana folders mirror the service tree**: the transformer also emits a `GrafanaFolder` for this service (uid `<platform>-<service>-folder`, `parentFolderUID: <platform>`), and every rule group and dashboard references it via `folderRef`. The `-folder` suffix keeps the folder uid out of the `<platform>-<service>-<purpose>` dashboard / `<platform>-<service>-<slug>-<severity>` group id space — Grafana draws folder and dashboard uids from one shared pool, so the app folder needs its own distinct identity. The parent platform folder (uid `<platform>`) is the platform's, created once — deterministic UIDs mean no ordering coordination (the operator retries until the parent exists). Nobody hand-creates folders in the UI.
- The LPSM "tree" is otherwise virtual — expressed by stamped labels, never by repo directories. Global assets (the generic dashboard, blanket alerts, routing configuration, the platform folder) are the platform's concern, not this repo's.

## Contract 3: strict on metrics and alerts, liberal on logs and traces

Metrics cost **active time series forever** and alerts cost **responder attention** — both default to NO and must justify themselves. Logs and traces are **deliberately liberal**: log and trace user/business events generously, with inputs and key variables, so event order and values are reconstructible when debugging — the platform's adaptive sampling manages volume. The one prohibition is unconditional spam (hot loops, per-tick polling). Every decision and its cost is recorded in `SIGNALS.md`. Details and rules of thumb: [Signal Decisions](./signals.md).

---

## Severity tiers and naming (cross-cutting)

| Severity      | Meaning                                     | Typical delivery       |
| ------------- | ------------------------------------------- | ---------------------- |
| `critical` 🚨 | Act now; user impact or imminent SLO breach | Pages on-call          |
| `warning` ⚠️  | Act during working hours; lead-time signal  | Team channel, no page  |
| `info` ℹ️     | Trend worth recording; nobody acts          | Archive channel / none |

Actual delivery per landscape/service is the platform routing configuration's decision, not the rule's.

The alert title is the **notification title** — the transformer prefixes it with the severity emoji (🚨/⚠️/ℹ️ — shape-distinct, colorblind-safe; derived from the tier **filename**, so a mismatch is unrepresentable), and the authored title stays **≤48 characters** so the final title survives a lock-screen push. The `severity` label remains the machine-readable source of truth on fired alerts. Tier count per signal is a deliberate choice (1 = binary failure, 2 = capacity default, 3 = only if the trend matters); not everything needs tiers — see [Alerts](./alerts.md).

---

## Verification (how each artifact is "tested")

The root folder ships no Kubernetes wrappers. Structural rules are enforced by the primordial-chart transformer (`required`/`fail` makes `helm template` refuse to render on violations, in CI and at every render). Semantic rules are a PR-review checklist; behavior is checked in Grafana itself.

| Artifact           | Enforced by the transformer                                                       | Review checklist (manual)                                                                         |
| ------------------ | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `SIGNALS.md`       | —                                                                                 | All gates answered + justified + costed; folders ↔ Gate-6 coverage both ways                      |
| Alert-set folder   | Required fields, severity enum, title ≤48 chars, `runbook.md` present, valid slug | Tier gaps >20%; `panel` points at the right panel of `overview.json`                              |
| Runbook + overview | —                                                                                 | Sections complete (Triage/Remediation/Escalation; overview's six sections)                        |
| Dashboard          | —                                                                                 | Lint → sandbox → render → visual checklist ([Grafana Dashboards](../grafana-dashboards/index.md)) |
| Deployed alert     | CR well-formed (render succeeds)                                                  | **Grafana Preview before merge** — the only check for an alert that can never fire                |

---

## Querying the backends (verify a signal exists before you chart or alert on it)

Query the deployment's signals with **`gcx`** — Grafana's agent-native CLI — against the deployment's
Grafana instance, which proxies to whatever backends its datasources point at. Discover, don't assume:

```bash
gcx datasources list                            # find the deployment's datasource UIDs
gcx metrics query -d <metrics-uid> '<promql>'
gcx logs    query -d <logs-uid>    '<logql>' --since 30m
gcx traces  query -d <traces-uid>  '<traceql>' --since 1h
```

Setup, auth (a query-scoped Grafana service-account token), the label model, ready-made recipes (ATS,
log volume, debugging), and THIS deployment's concrete values (server, UIDs, break-glass path) live in
the **`observability-query`** skill; the bundled gcx skills (`gcx agent skills install --all`) add
`debug-with-grafana`, `explore-datasources`, and `create-dashboard`.

Use these to **confirm a metric/label/log stream is actually collected before authoring** a panel or
alert against it — collector allowlists and per-app ServiceMonitors mean "queryable" is not automatic,
and an un-shipped series reads no-data. When authoring a dashboard, check **all three signals** for the
service, not just metrics (a trace panel is dead until something emits spans), and verify the query
ENGINE honours your constructs (dialects differ per backend and per version — keep the findings in the
repo's probe record, per the [dashboards standard](../grafana-dashboards/index.md)).

## Further Reading

- [Grafana Alerting: labels/annotations](https://grafana.com/docs/grafana/latest/alerting/fundamentals/alert-rules/annotation-label/) · [dynamic labels](https://grafana.com/docs/grafana/latest/alerting/best-practices/dynamic-labels/)
- [Google SRE workbook: alerting on SLOs](https://sre.google/workbook/alerting-on-slos/) · [postmortem culture](https://sre.google/workbook/postmortem-culture/)
