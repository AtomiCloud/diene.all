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

- `global.labelPrefix` is the only prefix input. Every service-tree label and annotation key reads it — wrapper-owned and pinned-dependency alike — and it must be one DNS-1123 subdomain, refused at the values schema and again at the helper. It lives under `global` because Helm propagates that table verbatim into every dependency, which is what lets one wrapper decision reach an upstream object; see [Upstream metadata interface](#upstream-metadata-interface).
- LPSM remains `{landscape, platform, service, module}`. The platform hostname slot always comes from the release namespace; a values file cannot stamp another platform.
- Ordinary hostnames are `<module>.<service>.<namespace>.<landscape>.<zone>`.
- Optional physical-instance hostnames are `<module>.<service>.<namespace>.<instance>.<landscape>.<zone>`. Instance is returned separately by the parser and never becomes an LPSM slot.
- Physical instance ids arrive as an already-minted **pair**, and the chart records both halves rather than deriving either. `global.instance.original` is the unchanged repository-qualified id — it may be far longer than one DNS label, up to 253 bytes, and is refused only for whitespace, control bytes, or characters outside `A-Za-z0-9._:/-`. `global.instance.label` is the authorized minter's stable DNS-1123 label for that id, at most 63 bytes, and is the **only** half that becomes a hostname segment (`instance.hostname`). Both are stamped, distinct, as `<prefix>/instance-original` and `<prefix>/instance-label`, which is what makes a hash-shortened label reversible and collision-auditable from the object itself. The two are recorded together or not at all: a missing key refuses at the generated schema's `required` list, an emptied half refuses at the helper as `InstancePairIncomplete`, and both empty simply record no instance.
  - The pair lives under `global` for the same reason `labelPrefix` does: Helm copies that table verbatim into every pinned dependency, so **one** resolved identity is reachable from an upstream template context. `upstream.global.annotations` therefore templates its two instance values through the wrapper's own `instanceOriginal`/`instanceSegment` helpers instead of naming literals. A chart-local `instance.*` table is not readable from a dependency's `tpl` context at all — it resolves to empty there — so the dependency had to hard-code a second copy, and that copy kept recording the physical pair while every wrapper-owned object switched to the receipt-bound petname: one release, one namespace, two different recorded physical instances. There is now exactly one configurable surface, so the two cannot diverge.
  - The **authorized minter owns** deterministic normalization, the stable hash that shortens a long id into one label, and the collision check across live allocations. This chart owns only boundary shape: it never lowercases, truncates, hashes, normalizes, or improvises one half from the other. Under `castform` preview the receipt-bound petname is recorded as both halves, because an assembler-minted petname is already its own unshortened id.
- Resource names use `<service>-<token>` with exactly one dash. Tokens fuse components (`main-cache` → `maincache`). Every enabled dependency receives an explicit conforming `fullnameOverride`.

The helpers are generic by design. Final environment-owned instance segments, hosted profile fixtures, and exposure semantics stay outside this node until their owning work lands.

### Upstream metadata interface

The pinned dependency is `app-template 5.0.1`, whose `bjw-s.common` library stamps `global.labels` and `global.annotations` onto every object it renders. Both library templates bind `$name := $k` and only `tpl`-render the **value**, so a map **key** reaches a rendered upstream object verbatim. A prefix override therefore used to move every wrapper-owned key while the upstream Deployment and Service kept `atomi.cloud` — and the labels gate excused them, so nothing reported it.

The wrapper closes that with one narrow, pinned interface:

- `global.labelPrefix` is a top-level `global` entry, so Helm copies it into the dependency's own values and an upstream template context can read it.
- `upstream.global.labels` and `upstream.global.annotations` write their keys as Helm templates — `'{{ .Values.global.labelPrefix }}/module'` — instead of literal strings. Overlays contribute their own slot the same way: the overlay owns the value, the shared prefix owns the key.
- `chart/templates/_helpers.tpl` **redefines** `bjw-s.common.lib.metadata.globalLabels` and `bjw-s.common.lib.metadata.globalAnnotations`. Helm's template namespace is global and `sortTemplates` parses deeper paths first, so the wrapper's shallow `templates/_helpers.tpl` is parsed after the dependency's `charts/upstream/charts/common/templates/lib/metadata/*.tpl` and a same-named definition replaces it for the whole render — including when the wrapper is rendered from a packaged archive, whose relative depths are identical. The replacements reproduce the upstream emission byte-for-byte and add exactly one thing: the key is `tpl`-rendered too. Every rendered key is then judged as a Kubernetes qualified name, so a computed key the API server would reject refuses at render instead of at apply.

This is a pinned coupling to a third-party template, not a public extension point, so `scripts/validate/helm-wrapper.sh labels` re-checks the interface against the vendored archive before it asserts any projection: the dependency version must be the measured one, both library templates must still exist under their measured names, they must still bind their map key verbatim, and the wrapper must still redefine both. A dependency bump that renames them would otherwise make the wrapper redefine nothing and silently drop every upstream service-tree key; a bump that starts templating its own keys makes the override redundant. Either finding means re-measure, not re-pin. The vendored archive itself is never edited.

The gate then holds both object families to the same rule under both the default prefix and an override: every slot of the stack's projection present and exact in labels **and** annotations, the recorded instance pair present in the annotations, and — under an override — no key surviving under the old prefix. Wrapper-owned objects project module `api` and the dependency's objects project module `upstream`; both lists are named, so an object that stops rendering is reported missing instead of quietly shrinking coverage. `probes/wrapper-lpsm-labels.ts` sabotages exactly one upstream label key back to a literal `atomi.cloud/…`, which leaves every default-prefix render byte-identical and can only be caught by the override runs.

A seventh stack renders with `global.instance.preview.enabled=true`, where both recorded halves are the receipt-bound petname, and holds the named upstream Deployment and Service to the same recorded identity as every wrapper-owned object. Two sabotage controls run beside it, each against a throwaway copy of the chart so the working tree is never touched: restoring `diene-helm-wrapper.labels` on the migration pod must redden hook isolation, and hard-coding the dependency's instance annotations back to the physical pair must stay invisible in physical mode — it is byte-identical there, exactly as the defect was — and redden on the preview stack.

### Preview identity boundary

`castform` preview names are governed by R-P9 and `concepts/environments.md` §3a. The canonical byte encoding, the digest, and the authorized assembler are build deliverables owned there. This chart is only their consumer: it never mints, canonicalizes, or suffixes a petname, and it never renders the internal `leaseKey` or full digest into an object or a hostname.

`global.instance.preview` is the whole boundary, and every field of it is verified at render time:

- the typed `canonical` instance must bind byte-for-byte to the `receipt` — a differing petname or a differing `fullLeaseDigest` refuses as `PreviewIdentityMismatch`;
- the receipt must be complete and versioned — a missing field, an unversioned `diene.preview-manifest` schema, an unversioned `diene.preview-wordlist`, a malformed digest or `leaseKey`, or a `forkSource` outside `staging | production` refuses as `PreviewIdentityUnavailable`;
- the petname must be a single lowercase DNS-1123 label matching `<noun>-<verb>-<noun>[-<3 base32hex chars>]`;
- the collision suffix is accepted only when the receipt records a live allocation holding the same base petname under a **different** full digest, and only when the three characters are the first three base32hex digest characters — read off the receipt's own `leaseKey`, never recomputed here. A caller-supplied suffix, a suffix with no recorded collision, a recorded collision with no suffix, and a "collision" against the same digest all refuse. Because the recorded name is the receipt's, it cannot change after mint even once the collision partner closes;
- the resolved manifest must be resolved: pin keys are `<platform>.<service>` with no module segment, pin values are a released version, a full commit, or exactly `{kind: operator, version: <v>}`, and a recorded branch resolution must name the commit the manifest already pins. A branch pin that never resolved, a `ref`-bearing pin, and a resolution that drifted past its mint commit all refuse, so a moving branch cannot move a rendered hostname.

The preview coordinate is `<module>.<service>.<namespace>.<previewPetname>.castform.<zone>`. Neither the platform slot nor the landscape slot is a values entry: platform comes from the release namespace and the landscape is the one ruled preview landscape.

`probes/wrapper-lpsm-hostnames.ts` carries the vectors — the accepted derivations plus every refusal above, each asserting the reason rather than only a non-zero exit. Where a rule is enforced at both the generated values schema and a template helper, it is **two separately named vectors**, never one whose reasons are OR-joined: an OR goes green the moment either boundary carries the whole refusal, so the schema alone could keep a slack helper looking asserted. The helper half re-runs the same bytes under `--skip-schema-validation`, which is what proves it is still reachable. The same split covers the DNS-1123 hostname slots, the dotted zone, the preview receipt, and the physical instance pair.

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

A hook is **not** the primary workload, so it does not wear the primary workload's selector identity. Every primary Service selector and the Deployment's own `matchLabels` are exactly `selectorLabels`, so a hook pod stamped with the full `diene-helm-wrapper.labels` set carries a strict **superset** of all of them and is eligible for their EndpointSlices for as long as the hook runs. Nothing routed only because both Services name `targetPort: http` while the migration container declares no port — an accident of this sample, not a property of the shape every `charts/*` node inherits. `diene-helm-wrapper.hookLabels` keeps everything that makes a hook a service-tree object (the full projection under the prefix in force, chart, version, managed-by, the recorded instance pair in the annotations) and swaps exactly the workload identity: `app.kubernetes.io/name` becomes the hook's own `<service>-<token>` name and `app.kubernetes.io/component` records which hook it is.

`scripts/validate/helm-wrapper.sh labels` asserts that directly rather than by inspection: every named selector-bearing object must render, must carry a non-empty selector, and must fail to select the hook pod, while the hook pod itself must still carry the exact projection and instance annotations — so the check cannot pass by matching nothing. Because that holds, `scripts/validate/helm-wrapper-k3d.sh` selects pods by the Deployment's own selector and no longer filters `batch.kubernetes.io/job-name` out of the result; the workaround existed only to hide this defect.

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

The `probes/` directory is the CyanPrint probe matrix that `cyanprint probe` runs in CI (`⚡reusable-helm-wrapper.yaml`). Two smoke baselines are **declared live-network controls**: `wrapper-upstream-latest` (skopeo resolves the real upstream chart and Podinfo image tags) and `wrapper-dependency-update` (`helm dependency update` resolves the real pinned upstream). Those two are the only rows that opt into offline tolerance, and they do it through `expectGreenOrOffline` in `probes/wrapper-offline.ts` — which also owns `isConnectivityFailure` and the local `probeInapplicable`. On a verified connectivity failure they throw `probeInapplicable` and the engine records that one row `invalid` (inapplicable) rather than `broken`.

That is a statement about which rows **tolerate** being offline, not a claim that they are the only rows that can ever touch the network. `wrapper-k3d-install` stands up a real k3d cluster and can still pull venue artifacts and images, and any row that reaches a package registry may do the same. Those rows simply have no offline branch: if their network is unreachable they fail as `broken`, exactly as an ordinary defect would.

The acceptance semantics are therefore: a matrix run is complete only when **every** row reached what it needed, and the inapplicable marker governs **only the smoke row that carries it** — it never sets, passes, or fails any other row's verdict. An inapplicable smoke control is a gap in the proof, not a pass: a matrix that recorded `invalid` on a live-network smoke has not demonstrated that reach, so its mutation runs are **untrusted** until the upstream is reachable and that row turns `proven`. Treat an inapplicable smoke row as "this probe asserts nothing here," then re-run the matrix against a reachable network before trusting it.

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
- `global.labelPrefix`;
- upstream chart name/version/repository and vendored archive filename, plus the measured dependency version the metadata-template override is pinned to;
- upstream image references used by `latest`;
- OCI organization/repository path and secondary git repository URL;
- landscape and cluster overlay filenames;
- k3d cluster and local registry names;
- repository-qualified physical instance id, its recorded DNS label, and the original-id annotation pair;
- preview receipt identity: assigned petname, manifest schema and word-list versions, `forkSource`, requester, and default-channel reference;
- selected hostname zone;
- CR API versions once their owning operators freeze them.

Held ENV profile names, final parser fixtures, frontend exposure rules, hosted substrate behavior, and final bootstrap enumeration are not tokenized here because this node does not own those decisions.
