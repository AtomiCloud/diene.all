# Helm wrapper baseline

This branch is the reusable platform-chart wrapper shape. It vendors a pinned upstream dependency, but wrapper-owned templates carry the contracts that every concrete platform chart must preserve.

## Rendering model

Render values in two independent dimensions:

1. `chart/values.yaml` — platform/service/module/layer defaults.
2. `chart/values.<landscape>.yaml` — landscape identity and landscape behavior.
3. `chart/values.<cluster>.yaml` — normally-thin cluster identity or genuine cluster overrides.

The sample stack is `values.yaml` → `values.example.yaml` → `values.lapras.yaml`. Landscape and cluster vocabularies must remain disjoint. Do not create cross-product filenames.

Run `pls build`, `pls example:lapras:template`, or `pls test:unit`. `pls test:int` creates an ephemeral k3d cluster, installs the local stack, waits for healthy pods, and proves an OCI push/pull against the cluster's local registry.

## Identity and naming

- `labelPrefix` is the only prefix input. Every service-tree label and annotation helper reads it.
- LPSM remains `{landscape, platform, service, module}`. The platform hostname slot always comes from the release namespace; a values file cannot stamp another platform.
- Ordinary hostnames are `<module>.<service>.<namespace>.<landscape>.<zone>`.
- Optional physical-instance hostnames are `<module>.<service>.<namespace>.<instance>.<landscape>.<zone>`. Instance is returned separately by the parser and never becomes an LPSM slot.
- Physical ids are repository-qualified before normalization. DNS-1123 labels longer than 63 characters are shortened with a stable hash, while original and normalized values are stored together as annotations.
- Resource names use `<service>-<token>` with exactly one dash. Tokens fuse components (`main-cache` → `maincache`). Every enabled dependency receives an explicit conforming `fullnameOverride`.

The helpers are generic by design. Final environment-owned instance segments, hosted profile fixtures, and exposure semantics stay outside this node until their owning work lands.

## Secrets and config

The wrapper assumes the platform SecretStore already exists. It emits one service-scoped ExternalSecret, targets one service Secret, and uses folder-level `dataFrom.find` plus rewrite rules:

- `/shared/X` → `SHARED_X`
- `/<service>/X` → `<SERVICE>_X`

Individual key mappings are forbidden. There is no secret-provider toggle.

Application config lives in root `config/*.yaml`. `scripts/local/vendor-chart-config.sh` copies it into ignored `chart/files/config/` immediately before chart build/render; `.Files.Glob` bundles those files into the ConfigMap. Generated copies are never committed.

## Workloads and migration

Reloader's annotation is emitted by default for every wrapper-owned workload. A workload can explicitly set its own `reloader.enabled: false` when automatic restart is unsafe.

The migration Job is a separate object with:

- `helm.sh/hook: pre-install,pre-upgrade`
- `argocd.argoproj.io/hook: PreSync`
- `helm.sh/hook-delete-policy: before-hook-creation`

The Deployment always uses `RollingUpdate`; the hook never recreates it.

## Rendered-manifest validation

`scripts/validate/helm-wrapper.sh rendered-manifests` runs the generic chart-bearing-repository stage:

1. Helm renders the stacked values.
2. kubeconform validates Kubernetes objects plus the checked-in local CR schemas.
3. Kyverno CLI evaluates definition-only native ValidatingAdmissionPolicy fixtures against the resources named by those policies' `resourceRules`. kubeconform still validates the complete render; the narrow Kyverno input avoids its offline GVR lookup failure on unrelated custom resources.

The local VAP profile covers explicit non-latest tags, requests/limits, non-root baseline-plus security, and the NodePort prohibition. The wrapper proves the wiring with one `:latest` fault; the future policy chart owns per-rule negative fixtures.

## Primordial helpers

The sample renders the frozen current shapes for `PlatformDependency`, `VirtualLandscapeService`, `LogtoApp`, `Problem`, and `CloudflareDeploy`:

- dependency delivery is exactly `external | local | replicated`;
- a v-landscape target has one writer plus `placement.preferredHost` and no sharing fields;
- VLS carries no free-form hostname;
- LogtoApp declares paths, `extraRedirectUris`, and `resourceRefs`, never per-row redirects;
- CloudflareDeploy uses `desiredVersionFrom.tag`, never a hand-pinned version id.

These are helper contracts, not CRD ownership. The T3/operator nodes own final API groups, controllers, and installed CRDs.

## Gateway and webhook conventions

The gateway Service is always `type: LoadBalancer`:

- AWS: deterministic subnet list paired positionally with NLB Elastic IP allocation ids. This path carries the standing EKS Auto Mode compatibility assumption until the user completes the live test.
- OCI: reserved public IP annotation.
- DigitalOcean: provider-lifetime-stable load balancer IP, with no fixed-IP annotation.

NodePort and hostPort are absent. TLS terminates at the gateway platform, not this Service.

Every gateway exposes `/healthz` and must return a 2xx response. Webhook receivers use `/internal/webhooks/{provider}` and respond `200` for processed, `421` for the wrong landscape owner, and another 4xx/5xx for a retryable error. The checked-in HTTPRoute is a scaffold only; product handlers implement the protocol.

## Publishing

OCI is the default publish/consume mode. Git chart repositories remain secondary. The only exception classes are the moving-tag fleet compiler and boot-time Primordial/seed charts; the exact bootstrap roster remains intentionally held for its owner.

`scripts/release/bump.sh` stamps `chart/Chart.yaml` at the release commit. `scripts/ci/publish.sh` refuses a manifest/tag mismatch, regenerates Helm docs, and supports git packaging plus OCI dry-run or push. No external publish is needed for local proof.

## Tokenization surface

Tokenize these isolated scalars when materializing an instance:

- chart and release name;
- `serviceTree` platform/service/module/layer values;
- `labelPrefix`;
- upstream chart name/version/repository and vendored archive filename;
- upstream image references used by `latest`;
- OCI organization/repository path and secondary git repository URL;
- landscape and cluster overlay filenames;
- k3d cluster and local registry names;
- repository-qualified physical instance id, normalized DNS label, and original-id annotation;
- selected hostname zone;
- CR API versions once their owning operators freeze them.

Held ENV profile names, final parser fixtures, frontend exposure rules, hosted substrate behavior, and final bootstrap enumeration are not tokenized here because this node does not own those decisions.
