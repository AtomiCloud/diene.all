# diene-nextjs-frontend-primordial

The **config chart** for `nextjs-frontend` (R20). It carries the objects that
live on the Primordial cluster and describe this service, not the objects that
run it.

Two charts, one service, a clean split:

| Chart                    | Owns                                                        |
| ------------------------ | ----------------------------------------------------------- |
| `infra/primordial_chart` | dependency CRs, Logto app, Grafana folder/dashboards/alerts |
| `infra/garden_app_chart` | the running workload (Deployment/Service/ServiceAccount)    |

This chart ships **no Kargo promotion machinery** — promotion is centralized on
Primordial and is not a per-service concern.

## Contents

| Template                  | Emits                                                        |
| ------------------------- | ------------------------------------------------------------ |
| `platformdependency.yaml` | one `PlatformDependency` per landscape (union of modules)    |
| `logtoapp.yaml`           | `LogtoApp` — the frontend is its own placement owner         |
| `grafana-folder.yaml`     | `GrafanaFolder`, uid `<platform>-<service>-folder`           |
| `grafana-dashboards.yaml` | one `GrafanaDashboard` per `observability/dashboards/*.json` |
| `grafana-alerts.yaml`     | one `GrafanaAlertRuleGroup` per alert severity file          |

## Observability is vendored, not symlinked

Root `observability/` is authoritative. Helm cannot read outside a chart
directory and rejects symlinks, so the build **copies** it in first:

```bash
scripts/local/chart-vendor.sh   # observability/ -> infra/primordial_chart/files/observability
helm template t infra/primordial_chart
```

`infra/primordial_chart/files/` is gitignored — regenerated every build, never
committed. Run the vendor script before any lint/template/package/publish.

`observability/` is currently an intentionally empty scaffold (zero dashboards,
zero alerts). Both Grafana templates render cleanly against it; content added
later is picked up with no chart change.

## Rendering contract

Derived from the primordial-chart standard, all enforced at render time:

- **Folder** — uid `<platform>-<service>-folder`, `parentFolderUID: <platform>`.
- **Dashboards** — `dashboards/{purpose}.json` → uid
  `<platform>-<service>-{purpose}`. The uid inside the JSON must match, or the
  render fails.
- **Alerts** — `alerts/{slug}/{severity}.yaml` → group
  `<platform>-<service>-{slug}-{severity}`, exactly one inline rule. Severity
  comes from the filename and picks the emoji (🚨 / ⚠️ / ℹ️).

The render **fails loudly** on: an unrecognized severity filename; a missing
title, datasource, expr, summary, or description; a title over 48 characters; a
missing `runbook.md` for an alert slug; invalid dashboard JSON or a mismatched
uid; a datasource outside the declared set; or an absent `serviceTree`.

## Identity

`serviceTree` mirrors `config/config.yaml` → `app.servicetree` (R21 — identity is
config, never a literal). Every slot is validated as a DNS-1123 label, which is
what lets a dashed service name like `nextjs-frontend` through while still
rejecting garbage.

`labelPrefix` (default `atomi.cloud`) is one configurable key; no helper
hard-codes it.

## Dependencies

`platformDependencies` declares one entry per landscape. The frontend is
stateless, so it declares exactly one: the `kv` (Upstash) store backing the
server-side auth session. Duplicate landscapes and empty module sets both fail
the render rather than silently collapsing.

## Verify

```bash
scripts/local/chart-vendor.sh
helm lint infra/primordial_chart
helm template t infra/primordial_chart | kubeconform -strict -summary -ignore-missing-schemas -
```

`-ignore-missing-schemas` is required: every object here is a CR
(`GrafanaFolder`, `GrafanaDashboard`, `GrafanaAlertRuleGroup`,
`PlatformDependency`, `LogtoApp`) whose schema is not in the upstream bundle.
