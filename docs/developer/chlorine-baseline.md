# Chlorine baseline

chlorine is the **pure passthrough stakater/reloader wrapper chart** for
AtomiCloud landscapes — the SIMPLEST wrapper instance and the parity check that
the helm-wrapper template needs zero bespoke additions. It is a materialized
product (S30): it inherits the helm-wrapper _shape_ — one label prefix,
namespace-sourced LPSM identity, Reloader opt-in, and rendered-manifest
validation — but **not** the template's CyanPrint probe matrix. There is no
`probes/`, no `features.json`, and no gate/smoke/presence probe classes; evidence
is an ordinary testing pyramid with negative fixtures as normal tests.

It wraps `stakater/reloader` **pinned chart 2.2.14 / app v1.4.19** (the current
official latest; this rebuild bumps the former sulfoxide/chlorine reloader chart
1.0.121). Reloader is the last hop of the secret-rotation chain
(Infisical rotate → ESO sync → **Reloader restart**): when a workload's
referenced Secret/ConfigMap changes, Reloader rolling-restarts that workload.

## Passthrough minimality

reloader renders one controller Deployment plus its RBAC (ClusterRole/Binding,
Role/Binding, ServiceAccount) — no CRDs, webhook, or cainjector. The wrapper adds
NO templates of its own beyond the `_helpers.tpl` partials and the wrapper-owned
`chlorine-lpsm` ConfigMap. Its overrides, all under the `reloader` alias, are:
the canonical `chlorine-reloader` `nameOverride`/`fullnameOverride`, the pinned
`image.tag`, the reload stance (`autoReloadAll: false`, `reloadStrategy:
default`), resource envelopes, container hardening, the Reloader self opt-in
annotation, and the static service-tree deployment labels. Own-template surface
== skeleton baseline is a conductor minimality sweep (S27), not a test here.

## Reload strategy — annotation opt-in

Reloader is **annotation opt-in, never auto-reload-all**. Only workloads carrying
`reloader.stakater.com/auto: "true"` are restarted; the helm-wrapper bakes that
opt-in into every family chart by default, omitted only for stateful/unsafe
workloads. `reloader.reloader.autoReloadAll` stays `false` — flipping it would
reload EVERY workload unless it opts out, the opposite of the fleet convention.
The `reloader` gate proves the default annotation on chlorine's own Deployment
and the values opt-out path; the `auto-reload-all` gate proves the flag is false
and no `--auto-reload-all` argument renders (negative: flipping the flag injects
the argument).

## Identity and labels

reloader has **no `global.commonLabels` passthrough**, so the static service-tree
labels (`service`/`module`/`layer`, plus `landscape` from the overlay) ride the
chart's own `reloader.deployment.labels` override onto the controller Deployment
and pod. The namespace-sourced platform label cannot be a static value, so the
wrapper-owned `chlorine-lpsm` ConfigMap carries the **full dynamic LPSM
projection**: platform = release namespace, the landscape/service/module/layer
slots, and reversible physical-instance annotations. `global.serviceTree.platform`
is forbidden as a value; platform always comes from the release namespace. The
`labels` gate checks the ConfigMap's full projection, namespace-follows-platform,
the `labelPrefix` override (which reprefixes the ConfigMap and leaves no
`atomi.cloud/*` key on it), deployment-labels↔serviceTree consistency, and that
the controller Deployment carries the static service-tree labels.

## Fullname convention

Every rendered DNS-subdomain object follows `<service>-<token>` (exactly one
dash, dash-less token): the Deployment/ServiceAccount are `chlorine-reloader` and
the wrapper ConfigMap is `chlorine-lpsm`, all via `fullnameOverride` / the
`chlorine.resourceName` helper. RBAC objects legitimately carry extra dashes and
are exempt. The `fullname` gate asserts the convention (negative: a two-dash
`fullnameOverride` reds it).

## Upstream selection

The vendored dependency is official reloader chart `2.2.14` / app `v1.4.19`,
pinned pure-passthrough from the recorded source archive hash in
`chart/upstream-evidence.yaml` (the current official latest).
`scripts/local/vendor-reloader.sh` verifies the vendored archive is exactly the
recorded upstream source (no patch). `pls latest` checks the official chart
repository and the `ghcr.io/stakater` image registry against the evidence; it
fails only if upstream has regressed below the pin, treating a genuinely newer
upstream as an informational note (adopting it is a `dep(reloader)` PR).

## Testing pyramid

The non-live unit/static tier (`scripts/ci/chlorine.sh`) includes: Helm
schema/lint/render over base and the landscape+cluster stack; a schema negative
plus the generated-schema drift gate; dependency version/hash verification and
official-latest evidence; default/override LPSM projection with namespace-sourced
platform rejection; the Reloader default/opt-out annotation gate and the
auto-reload-all hygiene gate; the fullname-convention gate; kubeconform + Kyverno
VAP over every stack (with the `:latest` sabotage); git/OCI packaging dry-runs and
version==tag mismatch rejection; release config/vocabulary and gitlint-type
equality; and required-file presence.

The integration tier (`scripts/validate/chlorine-k3d.sh`) creates an ephemeral
k3d cluster, installs the engine, waits for the `chlorine-reloader` Deployment to
become Available, and proves the SoS last hop: an annotated Deployment whose
referenced Secret changes is rolling-restarted, while an un-annotated Deployment
referencing an un-annotated Secret stays put (annotation opt-in, not
auto-reload-all).

## Tokenization

Per-instance/tokenized values are: chart and release names; OCI/git repository;
the namespace-derived platform plus service/module/layer; `global.labelPrefix`;
landscape and cluster overlay filenames; the reloader chart/app/image versions,
source archive hash, repository, and vendored archive filename; the ghcr image
registry; and the k3d cluster/registry names plus the repository-qualified
physical instance id and normalized label.
