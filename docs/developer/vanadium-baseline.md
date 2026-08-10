# Vanadium baseline

This chart is the fleet's single controller-free admission layer. It ships native
`ValidatingAdmissionPolicy` objects (GA in Kubernetes 1.30+) plus their bindings and
needs no controller, webhook, CRD, or running component. It replaces the retired
Kyverno engine (argon) and Kyverno policy set (sodium); there is no PSA namespace
label layer anywhere in the fleet (phosphorus is retired and never resurrected).

## Rendering model

Render values in two independent dimensions, exactly like the wrapper shape:

1. `chart/values.yaml` — prefix, fullname, four-slot service-tree projection, the
   cluster admission params, the exemption label key, and the per-policy
   enable + `validationActions` map.
2. `chart/values.<landscape>.yaml` — the cluster landscape stamped onto both the
   service-tree projection and the admission params that drive value-checking CEL.
3. `chart/values.<cluster>.yaml` — normally-thin cluster identity only.

The sample stack is `values.yaml` → `values.example.yaml` → `values.lapras.yaml`.
Landscape and cluster vocabularies stay disjoint; there are no cross-product files.

Run `pls test:unit` for the static tier (lint, render, schema, labels, fullname,
exemption, audit/enforce, and per-rule CEL conformance). `pls test:int` creates an
ephemeral k3d cluster, installs the policy set, and proves the warn-mode behavior;
that proof is reserved for the orchestrated live window.

## Identity and naming

- `labelPrefix` (default `atomi.cloud`) is the single prefix read by every label and
  annotation helper, including the keys baked into the CEL expressions.
- `fullnameOverride` is `<service>-<token>` with exactly one dash (`vanadium-admission`).
- Every rendered `ValidatingAdmissionPolicy` and binding name is `vanadium-<token>`
  where the token is the lowercased, dash-stripped policy key.

## Policy set

Each enabled policy renders one `ValidatingAdmissionPolicy` plus one
`ValidatingAdmissionPolicyBinding`. CEL expressions are object-only — admission
params (landscape, accepted platforms, accepted layers) are baked in as literals at
render time, so the definitions carry no `paramKind` and the generic rendered-manifest
validation stage can evaluate them offline with `kyverno apply`.

| Policy key               | Enforces                                                                |
| ------------------------ | ----------------------------------------------------------------------- |
| `requireLabels`          | the five LPSM keys exist as labels                                      |
| `requireAnnotations`     | the five LPSM keys exist as annotations                                 |
| `landscapeMatch`         | LPSM landscape label and annotation equal this cluster's landscape      |
| `layerRange`             | the LPSM layer is one of the accepted layers                            |
| `platformAccepted`       | the LPSM platform is in the accepted platform list                      |
| `disallowLatest`         | every normal/init image carries a final-path non-`latest` tag or digest |
| `requireResources`       | every container declares CPU and memory requests and limits             |
| `disallowNodePort`       | services are not `NodePort`                                             |
| `requireNonRoot`         | pod and every container run non-root                                    |
| `disallowPrivEscalation` | no container allows privilege escalation                                |
| `restrictVolumeTypes`    | PSS source whitelist; other sources rejected, alloy hostPath excepted   |

## Audit to enforce

The default fleet posture is the pre-enforcement pair `validationActions: [Warn, Audit]`.
Nothing is blocked; `Audit` writes only to the API-server audit log (gated on
EKS/DOKS), while `Warn` returns an admission warning to the applying client so the
violation is observable through ArgoCD apply logs. An enforcement landscape flips one
or more policies to `[Deny]` through the same per-policy `actions` value.

## Exemption convention

Exemptions are label-based, never hand-listed namespace or name globs. Every binding
carries a `matchResources.namespaceSelector` of `matchExpressions` that skips any
namespace labeled `<prefix>/<exemption.labelKey>: "true"` (default key
`policy-exempt`). Workloads that previously rode sodium name-glob excludes
(`*-cleanup-controller-*`, `*-container-logs-collector*`) get the equivalent namespace
label; the v1 escape hatch for a single workload is documented only and activates when
a workload first needs it.

`restrictVolumeTypes` implements the PSS restricted-source whitelist: `configMap`,
`csi`, `downwardAPI`, `emptyDir`, `ephemeral`, `persistentVolumeClaim`, `projected`,
and `secret` are allowed; every other source, including NFS, is rejected. The alloy
container-logs host-path mount is the sole additional scoped carve-out, not a namespace
exemption: `/var/log` and `/var/log/...` are allowed only for the `alloy-logs` service
account. k8s-monitoring's `podLogsViaKubernetesApi` is the documented hostPath-free
alternative, deliberately not chosen.

## Compliance view

There is a compliance view on every managed cloud with zero new components:

1. apiserver VAP metrics (per-policy deny/audit counters) flow to
   VictoriaMetrics and a Grafana dashboard.
2. per-object detail rides the `Warn` channel — all applies flow through ArgoCD, so
   warnings land in ArgoCD pod logs, which aluminium already ships to
   Gigapipe/ClickHouse for a Grafana LogQL view.

trivy-operator stays dropped fleet-wide and is not a fallback.

## Sodium to vanadium parity

Every sodium policy maps to a vanadium CEL policy or a documented drop; there is no
PSA column because vanadium is the sole admission target. Every sodium exclude maps to
the label-based exemption convention above.

| sodium policy / mechanism                                                                             | vanadium mechanism                                                         | status               |
| ----------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- | -------------------- |
| require LPSM labels                                                                                   | `requireLabels`                                                            | implemented          |
| require LPSM annotations                                                                              | `requireAnnotations`                                                       | implemented          |
| landscape label/annotation == cluster landscape                                                       | `landscapeMatch`                                                           | implemented          |
| layer value range                                                                                     | `layerRange`                                                               | implemented          |
| platform accepted list                                                                                | `platformAccepted`                                                         | implemented          |
| disallow `:latest` image tags                                                                         | `disallowLatest`                                                           | implemented          |
| require requests + limits                                                                             | `requireResources`                                                         | implemented          |
| disallow NodePort services                                                                            | `disallowNodePort`                                                         | implemented          |
| run-as-non-root (pod + container)                                                                     | `requireNonRoot`                                                           | implemented          |
| PSS disallow privilege escalation                                                                     | `disallowPrivEscalation`                                                   | implemented          |
| PSS restrict volume types                                                                             | PSS source whitelist (+ alloy `/var/log` hostPath carve-out)               | implemented          |
| namespace name-glob excludes (`kube-system`, `*-cleanup-controller-*`, `*-container-logs-collector*`) | namespace-label exemption (`<prefix>/policy-exempt: "true"`)               | redesigned as labels |
| workload-level name-glob excludes                                                                     | namespace-level exemption in v1; per-workload escape hatch documented only | documented           |
| Kyverno engine (argon)                                                                                | native VAP CEL — no engine, no CRDs, no controller                         | dropped, replaced    |
| PSA namespace labels (phosphorus)                                                                     | none — dropped fleet-wide                                                  | dropped              |

## Policy definitions

The chart templates are the single source of truth for the policy set. Each enabled
rule renders one `ValidatingAdmissionPolicy` (the definition) plus one
`ValidatingAdmissionPolicyBinding`; the definition objects carry no `paramKind`, so
they are directly consumable by the generic rendered-manifest validation stage
(Q-G20). Inheriting repos extract the definition objects from a render of
this chart and run them through `kyverno apply`; they carry one wiring sabotage each
and never per-rule fixtures.

`scripts/validate/vanadium.sh conformance` extracts the definitions from a fresh
render into a temporary directory (dropping the bindings) and regresses every rule.
Per-rule negative proof lives only in this chart under `chart/tests/cases/<token>/` —
one `good.yaml` that passes the policy and one `bad.yaml` that reddens it.

## Tokenization surface

Tokenize these isolated scalars when materializing an instance:

- chart and release name, and `fullnameOverride`;
- `serviceTree` platform/service/module/layer values;
- `labelPrefix`;
- the exemption `labelKey`;
- the admission params (landscape, accepted platforms, accepted layers);
- per-policy enable flags and `validationActions`;
- landscape and cluster overlay filenames;
- k3d cluster name for the integration proof;
- OCI organization/repository path and secondary git repository URL;
- the chart package filename (derived from `Chart.yaml` `name`).

Held ENV profile rosters, final compliance-backend dashboards, and the cross-stack
Grafana/ClickHouse view are not tokenized here — they are conductor/SIT-level concerns.
