# Aluminium baseline

aluminium is the AtomiCloud wrapper around [grafana/k8s-monitoring](https://github.com/grafana/k8s-monitoring) v4.x. It is a materialized platform chart (S30) that ships ONE wrapped telemetry stack — the Alloy Operator plus two Alloy collectors — and serves the fleet OTLP contract. It replaces silicon's collector fleet and lithium's OpenTelemetry Operator.

Read the linked Helm, service-tree, validation, testing, and release standards before editing this surface.

## Topology

- **alloy-metrics** — StatefulSet controller with clustering enabled; hosts the fleet OTLP receiver on `:4318` (http/protobuf, R14/R17) via the `applicationObservability` feature → collector assignment.
- **alloy-logs** — DaemonSet controller, no clustering, with a scoped `/var/log` mount (`alloy.mounts.varlog`).
- Both collectors are **Alloy CRs** rendered by k8s-monitoring; the Alloy Operator materializes the StatefulSet/DaemonSet at runtime.
- All other k8s-monitoring features stay OFF: events singleton, beyla, profiling, opencost/cost, selfReporting. Only `applicationObservability`, `clusterMetrics`, and `podLogsViaOpenTelemetry` are enabled.

## Destinations (OTLP-everywhere, Q-I28)

- Every outbound signal uses OTLP/HTTP — one protocol, **no per-signal protocol selector**.
- `victoriametrics` — OTLP, metrics only (VictoriaMetrics is OTLP-native).
- `gigapipe` — OTLP, logs + traces (single Go binary on the existing ClickHouse; Grafana queries it via standard Loki + Tempo datasources).
- Destination naming is always **gigapipe** (never `qryn` — the legacy Node repo).
- Endpoints are overlay-owned: local/Garden point at the emulated tier-1 stack; prod endpoints are supplied by Primordial. aluminium only carries the destination shape and per-landscape endpoint config in overlays.

## Identity and naming

- Chart name `diene-charts-aluminium`; LPSM projection `serviceTree` = `telemetry` platform/module, service `aluminium`, layer `1`.
- `labelPrefix` is the single configurable service-tree prefix (default `atomi.cloud`), read by every `_helpers.tpl` helper. aluminium's own ExternalSecret carries the LPSM labels via those helpers.
- Both collectors carry the LPSM labels via the upstream `collectors.<name>.alloy.labels` injection (the wrapper surface sets them in `values.yaml`).

## Secrets and config

- aluminium's only own template is the **ExternalSecret** (backend creds via ESO, SoS chain). It assumes the platform SecretStore created by carbon and declares `dataFrom` against `/shared/aluminium` and `/svc/aluminium` with the folder-prefix rewrite convention (`SHARED_*`, `ALUMINIUM_*`). No literal credentials are ever inlined.
- Local and Garden run `auth: { type: none }` against the emulated stack; the ExternalSecret is the prod path and is disabled by default (`secret.enabled: false`).
- There is no config vendoring, migration hook, gateway, webhook route, or primordial CR — those are S27-absent for a telemetry platform chart.

## Workloads and policy

- The collector Alloy CRs are configured conformant: resources (requests + limits), bounded securityContext, and LPSM labels at the `spec.alloy` level.
- The strict baseline conformance of k8s-monitoring's **ancillary workloads** (alloy-operator Deployment, kube-state-metrics, node-exporter DaemonSet, helm hooks) is owned by **vanadium's** scoped-allowance VAP policy set (the `charts/vanadium` node). node-exporter legitimately requires hostNetwork + hostPath (`/proc`, `/sys`, `/`); the goal's design intent is that vanadium's CEL policy allows the specific host paths for alloy's ServiceAccount only — no blanket namespace exemption. Full ancillary-workload VAP conformance is therefore a serialized-proof tail, not a unit-tier assertion.

## Rendered-manifest validation (Q-G20)

The inherited stage runs on every render:

1. `helm template` over the stacked values (base → landscape → cluster).
2. `kubeconform` (k8s + local CRD schemas, including `schemas/alloy.json`).
3. Kyverno `apply` of `policies/vap` (VAP definitions only) — the ONE wiring sabotage (a `:latest` image fixture) is caught, proving the stage cannot silently stop matching.

Complements — does not replace — `helm lint`.

## Tokenization surface

Every per-instance scalar in this chart:

- chart/release name (`diene-charts-aluminium`) · serviceTree platform/service/module/layer · `labelPrefix` value · upstream dep name+version+repository (`grafana/k8s-monitoring` v4.x) · vendored tgz filename (`k8s-monitoring-<ver>.tgz`) · skopeo image refs in `latest` (grafana/alloy) · OCI/ghcr org path · git repo URL · landscape overlay filenames (`values.<landscape>.yaml`) · cluster overlay filenames (`values.<cluster>.yaml`) · k3d cluster name · destination endpoint hostnames (overlay-owned).

## Publishing

OCI is the default (publish + consume via OCI); git-as-chart-repo is the secondary mode. `scripts/ci/publish.sh` stamps the Chart.yaml version via yq (manifest == tag) and runs helm-docs.

## Held boundaries

- No final ENV-owned profile names, frontend in-cluster chart, public-callback exposure, CI preview lanes, or live managed-backend proof (k3d/live integration is reserved for serialized orchestration-authorized proof).
- Prod telemetry backend (Tempo/Loki/Mimir tenancy, Primordial endpoints) is out of diene scope — aluminium only carries per-landscape endpoint config in overlays.
