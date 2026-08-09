# Primordial-Chart Grafana Rendering

Every deployable service owns its observability resources in its own
**primordial chart**. That chart is deployed to Primordial, where the Grafana
Operator runs. The runtime app chart stays pure runtime, and there is no central
many-repository observability chart.

## Source and generated copy

The repository root is authoritative:

```text
observability/
├── SIGNALS.md
├── overview.md
├── dashboards/*.json
└── alerts/{slug}/{critical|warning|info}.yaml
```

Helm cannot read outside the chart directory. The chart build therefore copies
the root directory into a gitignored generated location inside
`infra/primordial_chart/`. The copy is regenerated before lint, template,
package, or publish; it is never hand-edited or committed. The repository adds
its own ignore block when the chart exists.

## One source file, one resource

The helm-wrapper implementation must preserve these mechanical mappings:

| Source                          | Rendered resource                                                          |
| ------------------------------- | -------------------------------------------------------------------------- |
| Service identity                | One `GrafanaFolder` with uid `<platform>-<service>-folder`                 |
| `dashboards/{purpose}.json`     | One `GrafanaDashboard` with uid `<platform>-<service>-<purpose>`           |
| `alerts/{slug}/{severity}.yaml` | One `GrafanaAlertRuleGroup` named `<platform>-<service>-<slug>-<severity>` |

Each alert group contains exactly one rule. A single `.Files.Glob` loop parses
one flat YAML dictionary, validates required fields, derives severity and emoji
from the filename, and emits the CR. It must not assemble arrays across files or
perform structural YAML surgery.

## Injected identity

The source definitions contain no Kubernetes wrapper and no hand-authored LPSM
labels. The renderer merges the chart's `serviceTree` values into every rule:

```yaml
labels:
  severity: critical
  landscape: raichu
  platform: tracker
  service: zinc
  module: webhook
```

The example values illustrate the mapping only; each chart supplies its own
values. Alert routing remains central and label-driven, never embedded in the
rule file.

The service folder references its deterministic platform parent folder. Every
dashboard and alert group references the service folder. Alert annotations are
derived from the source path and repository identity:

- `runbook_url` points to the set's own committed `runbook.md`.
- `__dashboardUid__` points to the curated overview dashboard when `panel` is
  present; otherwise the alert links to the generic LPSM dashboard.
- `__panelId__` is copied from the authored `panel` field.

## Structural validation

Rendering fails before any resource is emitted when:

- a severity filename is not `critical.yaml`, `warning.yaml`, or `info.yaml`;
- the alert dictionary is missing `title`, `datasource`, `expr`, `summary`, or
  `description`;
- a title exceeds 48 characters;
- the alert set has no `runbook.md`;
- a dashboard file is invalid JSON or lacks the expected deterministic uid;
- required `serviceTree` values are absent.

Dashboard semantics and alert query behavior still require the standard's
sandbox/Preview review. A successful Helm render proves structure, not that a
query returns real data.

## Ownership boundary

- O1 owns this mapping and the root source skeleton.
- `helm-wrapper` owns reusable template/helper implementation.
- Each consumer owns its primordial chart, source content, lint/render/install
  evidence, and real alert/dashboard review.
- The conductor owns cross-repository payload equality and topology checks.
