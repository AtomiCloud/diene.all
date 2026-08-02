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
- Physical instance ids arrive already minted. `instance.original` must already be one DNS-1123 label; the chart records it verbatim as both `<prefix>/instance-original` and `<prefix>/instance-label` and refuses anything it would have to lowercase, truncate, or hash. Repository qualification and any shortening happen at the authorized minter, never here.
- Resource names use `<service>-<token>` with exactly one dash. Tokens fuse components (`main-cache` → `maincache`). Every enabled dependency receives an explicit conforming `fullnameOverride`.

The helpers are generic by design. Final environment-owned instance segments, hosted profile fixtures, and exposure semantics stay outside this node until their owning work lands.

### Preview identity boundary

`castform` preview names are governed by R-P9 and `concepts/environments.md` §3a. The canonical byte encoding, the digest, and the authorized assembler are build deliverables owned there. This chart is only their consumer: it never mints, canonicalizes, or suffixes a petname, and it never renders the internal `leaseKey` or full digest into an object or a hostname.

`instance.preview` is the whole boundary, and every field of it is verified at render time:

- the typed `canonical` instance must bind byte-for-byte to the `receipt` — a differing petname or a differing `fullLeaseDigest` refuses as `PreviewIdentityMismatch`;
- the receipt must be complete and versioned — a missing field, an unversioned `diene.preview-manifest` schema, an unversioned `diene.preview-wordlist`, a malformed digest or `leaseKey`, or a `forkSource` outside `staging | production` refuses as `PreviewIdentityUnavailable`;
- the petname must be a single lowercase DNS-1123 label matching `<noun>-<verb>-<noun>[-<3 base32hex chars>]`;
- the collision suffix is accepted only when the receipt records a live allocation holding the same base petname under a **different** full digest, and only when the three characters are the first three base32hex digest characters — read off the receipt's own `leaseKey`, never recomputed here. A caller-supplied suffix, a suffix with no recorded collision, a recorded collision with no suffix, and a "collision" against the same digest all refuse. Because the recorded name is the receipt's, it cannot change after mint even once the collision partner closes;
- the resolved manifest must be resolved: pin keys are `<platform>.<service>` with no module segment, pin values are a released version, a full commit, or exactly `{kind: operator, version: <v>}`, and a recorded branch resolution must name the commit the manifest already pins. A branch pin that never resolved, a `ref`-bearing pin, and a resolution that drifted past its mint commit all refuse, so a moving branch cannot move a rendered hostname.

The preview coordinate is `<module>.<service>.<namespace>.<previewPetname>.castform.<zone>`. Neither the platform slot nor the landscape slot is a values entry: platform comes from the release namespace and the landscape is the one ruled preview landscape.

`probes/wrapper-lpsm-hostnames.ts` carries the vectors — the accepted derivations plus every refusal above, each asserting the reason rather than only a non-zero exit.

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

`scripts/validate/helm-wrapper.sh rendered-manifests` runs the generic chart-bearing-repository stage over **all three value stacks** — `values.yaml` alone, `values.yaml` → `values.example.yaml`, and `values.yaml` → `values.example.yaml` → `values.lapras.yaml`. The overlays disable objects the base stack renders, so a stage that only ever rendered the deepest stack would never kubeconform the CR-bearing shapes that only the shallower stacks render. Those extra stacks add CR schema coverage and broaden the per-definition policy sweep over each stack's core objects — not multiple-stack policy coverage of CRs, which are deliberately never policy-fed (the group filter below keeps custom resources out of Kyverno, whose offline runner cannot resolve their GVRs, so kubeconform is the only stage that ever sees a CR). Each stack runs the same four steps:

1. Helm renders that stack.
2. kubeconform validates every rendered object against Kubernetes plus the checked-in local CR schemas.
3. Kyverno CLI evaluates the definition-only native ValidatingAdmissionPolicy set, as a whole, against the rendered objects whose API group is named by the pinned policies' `resourceRules`.
4. The same objects are re-evaluated **one definition at a time**. Each definition must apply cleanly and report at least one `pass` in its detailed results, so a definition that silently stops matching anything is caught instead of hiding inside a green aggregate summary.

The Kyverno input is filtered by API **group**, never by kind. Today `resourceRules` name `""`, `apps`, and `batch`, so core objects no current rule matches — ConfigMaps included — are still fed in. That breadth is deliberate: a group-level filter keeps whatever kinds those rules grow into, so a future rule cannot be quietly excluded by a stale kind list, while still keeping out the custom resources whose GVRs Kyverno cannot resolve offline. kubeconform still validates the complete render, so nothing is dropped from schema checking.

The checked-in definition set is an exact, object-only extraction from the measured `charts/vap-policies` artifact. `policies/vap-interface.json` is the single source of that provenance — it records the source ref, the extraction commit under `sourceArtifactCommit`, the ratchet acceptance state at build under `ratchetAcceptanceAtBuild`, the extraction contract, and a SHA-256 for every definition. Read the lock for the commit and the acceptance state rather than this page; they move without a documentation edit, and later acceptance compares exact bytes without turning the measurement into authority. `scripts/validate/vap-interface.sh` re-checks the file set and every hash with `sha256sum` — coreutils rather than `nix hash file`, so the lock stays verifiable wherever the CI toolchain runs without Nix — and the rendered-manifest stage refuses to start until that passes. Because the bytes are pinned, `policies/vap/**` is excluded from the tree formatter in `nix/fmt.nix`; reformatting a borrowed definition would break its own lock. No bindings or per-rule fixtures are borrowed.

The six offline definitions cover explicit non-latest tags, NodePort, privilege escalation, non-root execution, requests/limits, and restricted volume types, and the per-definition loop proves each of the six is exercised by every stack. This wrapper owns only the generic render → kubeconform → policy-engine interface and one `:latest` wiring sabotage. The downstream `charts/vap-policies` node owns policy materialization, bindings, and per-rule negative fixtures; its graph edge follows this wrapper, so the snapshot is not a dependency claim.

## Probe matrix acceptance

The `probes/` directory is the CyanPrint probe matrix that `cyanprint probe` runs in CI (`⚡reusable-helm-wrapper.yaml`). Two smoke baselines are **live-network** controls: `wrapper-upstream-latest` (skopeo resolves the real upstream chart and Podinfo image tags) and `wrapper-dependency-update` (`helm dependency update` resolves the real pinned upstream). They are the only probes whose green path genuinely requires the public network, so they run through `expectGreenOrOffline`: on a verified connectivity failure (`isConnectivityFailure` in `probes/lib/helpers.ts`) they throw `probeInapplicable`, and the engine records that one row `invalid` (inapplicable) rather than `broken`.

Full matrix acceptance therefore requires **reachable upstreams**. The inapplicable marker governs **only the smoke row that carries it** — it never sets, passes, or fails any other row's verdict. But an inapplicable smoke control is a gap in the proof, not a pass: a matrix that recorded `invalid` on a live-network smoke has not actually demonstrated that reach, so its mutation runs are **untrusted** until the upstream is reachable and that row turns `proven`. Treat an inapplicable smoke row as "this probe asserts nothing here," then re-run the matrix against a reachable network before trusting it.

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
- repository-qualified physical instance id, its recorded DNS label, and the original-id annotation pair;
- preview receipt identity: assigned petname, manifest schema and word-list versions, `forkSource`, requester, and default-channel reference;
- selected hostname zone;
- CR API versions once their owning operators freeze them.

Held ENV profile names, final parser fixtures, frontend exposure rules, hosted substrate behavior, and final bootstrap enumeration are not tokenized here because this node does not own those decisions.
