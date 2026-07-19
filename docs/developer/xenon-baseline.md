# Xenon baseline

xenon is the **conditional metrics-server wrapper chart** for AtomiCloud
landscapes. It is a materialized product (S30) and an **edge chart** (Q-I32):
it inherits the helm-wrapper shape—one label prefix, namespace-sourced LPSM
identity, exact-one-dash controllable names, Reloader opt-in, and rendered-
manifest validation—but not the template's CyanPrint probe matrix.

It wraps `kubernetes-sigs/metrics-server` to provide the resource metrics API
used by HPA and `kubectl top`. The service-template-only migration Job, config
vendoring, and ExternalSecret surfaces are absent.

## Conditional enablement

`metricsServer.enabled` gates the dependency and the wrapper ConfigMap, so an
OFF stack renders no resources while the chart remains installable.

`chart/toggle-map.yaml` is the authoritative provider × named-landscape map:

| Provider      | Named landscapes       | Preinstalled | Xenon | Kubelet TLS                                   |
| ------------- | ---------------------- | ------------ | ----- | --------------------------------------------- |
| EKS classic   | pichu, pikachu, raichu | no           | ON    | secure                                        |
| EKS Auto Mode | pichu, pikachu, raichu | no           | ON    | secure                                        |
| DOKS          | pichu, pikachu, raichu | no           | ON    | secure                                        |
| on-prem       | onprem                 | no           | ON    | secure baseline; cluster overlay may add args |
| k3s/k3d       | lapras                 | yes          | OFF   | bundled                                       |

Every provider entry references named landscapes. The unit gate renders each
referenced committed stack and requires actual resource presence to equal both
the provider and landscape expectations. It also requires the exact provider
and landscape inventories above. A real negative rewrites the lapras overlay
from OFF to ON and invokes the same checker, which must fail.

The final Garden profile roster and membership decisions beyond this chart's
named enablement contract remain outside xenon.

## Stacked values

Values retain the independent landscape → cluster stacking model:

- `values.pichu.yaml`, `values.pikachu.yaml`, and `values.raichu.yaml` are the
  named cloud landscape overlays; each explicitly keeps xenon ON and secure TLS.
- `values.onprem.yaml` is the named on-prem posture; it stays ON, while a real
  cluster overlay may add provider-specific kubelet arguments.
- `values.lapras.yaml` owns the lapras OFF decision.
- `values.k3d.yaml` is the thin cluster-identity overlay stacked after lapras.

The local OFF stack is therefore base → `values.lapras.yaml` →
`values.k3d.yaml`. `pls lapras:k3d:template` renders it as empty output.

## Identity propagation

Helm `global` values are the supported parent-to-subchart channel and the
single identity source:

- `global.labelPrefix` defaults to `atomi.cloud`.
- `global.serviceTree` owns service `xenon`, module `metrics`, and layer `1`;
  landscape and cluster arrive from overlays.
- platform is **never a value**. Every wrapper and dependency helper renders it
  directly from `.Release.Namespace`; an attempted
  `global.serviceTree.platform` value fails rendering.

The wrapper ConfigMap and the actual metrics-server Deployment metadata and pod
template all carry the LPSM labels and annotations. Overriding
`global.labelPrefix=example.dev` changes all four workload metadata maps and
leaves no `atomi.cloud/*` LPSM key behind. Rendering to another namespace changes
the workload platform metadata to that namespace.

The upstream chart does not expose templated LPSM metadata or configurable RBAC
names. `scripts/local/vendor-metrics-server.sh` therefore applies the small,
version-pinned `chart/patches/metrics-server-3.13.1-xenon.patch` after Helm
dependency build/update. The patch uses Helm global values, touches only upstream
helpers/names and Deployment metadata, is reverse-dry-run verified, and is packed
deterministically. Source and patched SHA-256 values are recorded in
`chart/upstream-evidence.yaml`.

## Naming

Every controllable rendered Kubernetes object's `metadata.name` is
`<service>-<dashless-token>`:

- core Deployment, Service, ServiceAccount, ClusterRole, and binding:
  `xenon-metrics`;
- wrapper projection: `xenon-lpsm`;
- additional RBAC tokens: `xenon-reader`, `xenon-authreader`, and
  `xenon-authdelegator`;
- optional upstream objects use fused tokens such as `xenon-nannybinding`.

The one unavoidable exception is APIService `v1beta1.metrics.k8s.io`: Kubernetes
API aggregation requires the object name to be `<version>.<group>`. The fullname
gate enumerates every rendered object, permits exactly that one exception, and
also verifies every controllable ClusterRoleBinding reference resolves to the
renamed ClusterRole. Fixed external role references such as
`system:auth-delegator` are Kubernetes contracts, not xenon-owned object names.

## Upstream version selection

The official repository selection observed on 2026-07-19 is metrics-server chart
`3.13.1`, app/image `0.8.1`; the wrapper Kubernetes floor is consequently raised
to 1.31, matching upstream's 0.8.x compatibility matrix. The source archive hash
is pinned before the integration patch is applied.

The registry also exposes image `v0.9.0`, released 2026-07-13. It is not selected:
the official Helm repository still has no chart for it, and upstream documents
0.9.x as Kubernetes 1.34+. `chart/upstream-evidence.yaml` records that exact
fact rather than silently calling the older app image "latest". `pls latest`
checks both official repositories against the committed evidence and identifies
`3.13.1/0.8.1` as the newest released chart contract.

## Workload and policy posture

- Two replicas are the managed-cloud/on-prem default.
- Reloader is ON through the upstream `podAnnotations` surface and can be set to
  string `"false"`; the dependency integration supplies LPSM annotations
  independently, so opt-out cannot erase identity.
- Pod/container security contexts provide non-root execution, dropped
  capabilities, a read-only root filesystem, and CPU/memory requests and limits.
- The Q-G20 stage renders every enabled named landscape, validates Kubernetes
  schemas with kubeconform, and evaluates the workload/Service against the VAP
  definitions with Kyverno. Its `:latest` wiring mutation must fail.

## Testing pyramid

The non-live unit/static tier includes:

- Helm schema/lint/render over base and every committed named stack;
- a real schema negative (`metricsServer.replicas: 0`) plus the independent
  generated-schema drift gate;
- patched dependency version/hash/application verification and official latest
  evidence;
- default and override LPSM metadata on Deployment and pod, namespace-sourced
  platform rejection, Reloader default/opt-out, and exhaustive fullname checking;
- every provider × landscape toggle entry plus the lapras OFF→ON negative;
- kubeconform/VAP validation for each ON stack and the `:latest` sabotage;
- git and OCI packaging dry-runs and version/tag mismatch rejection.

The integration tier is reserved. `scripts/validate/xenon-sit.sh` requires an
enabled cloud/on-prem context plus explicit namespace, release, and **absolute,
empty** evidence directory. It refuses an existing release, installs with Helm
`--atomic --cleanup-on-fail`, captures separate complete stdout/stderr files for
install, rollout, status, both `kubectl top` calls, and cleanup, validates deployed
status and data rows, and retains whole-run `sit.stdout`/`sit.stderr` transcripts.
It then uses an ownership-claim-gated EXIT trap to uninstall. Cleanup failure is
recorded and makes the run fail. The script must not run on lapras/k3d.

## Publishing and tokenization

OCI is the default publish path; git-as-chart-repository remains secondary.
`scripts/ci/publish.sh` reproduces the patched dependency before packaging, runs
helm-docs, and enforces chart version = tag.

Per-instance/tokenized values are: chart and release names; OCI/git repository;
the namespace-derived platform plus service/module/layer; `global.labelPrefix`;
named landscape and cluster overlay filenames; the enablement/TLS matrix;
metrics-server chart/app/image versions, source and patched hashes, repository,
patch filename, and vendored archive filename; k3d cluster/registry names; and
the repository-qualified physical instance id plus normalized label.
