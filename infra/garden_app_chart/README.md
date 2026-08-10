# diene-nextjs-frontend-garden-app

The optional in-cluster **Garden** rail for `nextjs-frontend` (Q-ENV14). The
default rail is Cloudflare Workers; this chart exists so the same service can
also run as an ordinary Kubernetes workload on any of the seven ratified
profiles, from one immutable image.

## What this chart owns

Exactly three narrowly owned objects, and nothing else:

| Object           | Notes                                                   |
| ---------------- | ------------------------------------------------------- |
| `Deployment`     | one container, the standalone Node server               |
| `Service`        | `ClusterIP` only — no other type is representable       |
| `ServiceAccount` | optional (`serviceAccount.create`), token never mounted |

## What this chart deliberately does NOT own

No `Gateway`, `ListenerSet`, `HTTPRoute`, `Certificate`, `Issuer`,
`ClusterIssuer`, `Ingress`, Boron object, kgateway object, cert-manager object,
or callback-tunnel object. No `Secret` and no `ConfigMap` either.

Edge and DNS belong to Garden's `exposure-compile` action. This chart only
_declares_ what it wants exposed; Garden materializes it. That boundary is what
keeps one chart valid across a Boron landscape, a loopback landscape, and a
hosted vcluster without branching.

Runtime config is projected as container **env**, not a ConfigMap. That is on
purpose: with no config object to read, there is no client-visible surface a
secret could leak through. Secrets arrive only by reference
(`runtime.secretRefs` / `runtime.secretEnv`) and are never templated here.

## Identity

Identity is config, never a literal (R21). The dotted surface name is

```
<module>.<service>.<platform>.<instance>.<landscape>.<zone>
```

e.g. `webapp.nextjs-frontend.diene.dev.lapras.admin.atomi.cloud`.

`instance` is a **projection parameter, not a fifth LPSM slot**. It lives at the
top level, carries its own `<prefix>/instance` label, and is structurally barred
from `serviceTree` — the schema sets `additionalProperties: false` there, so
`serviceTree.instance` is a validation error, not a silent extra label.

`labelPrefix` (default `atomi.cloud`) is one configurable key; no helper
hard-codes it.

## Profiles

One file per ratified profile in `profiles/`. Render with a single overlay:

```bash
helm template my-release infra/garden_app_chart -f infra/garden_app_chart/profiles/eevee.yaml
```

| Profile  | Instance  | Exposure mode        | Image  |
| -------- | --------- | -------------------- | ------ |
| `lapras` | `dev`     | `boron-direct`       | digest |
| `ditto`  | `local`   | `local-loopback`     | tag    |
| `rotom`  | `ci`      | `local-loopback`     | tag    |
| `absol`  | `ci`      | `local-loopback`     | tag    |
| `eevee`  | `preview` | `entei-service-sync` | digest |
| `plusle` | `preview` | `entei-service-sync` | digest |
| `minun`  | `preview` | `entei-service-sync` | digest |

Hosted vclusters (`eevee`/`plusle`/`minun`) are **truncated-LAPRAS**: no inner
kgateway, no cert-manager, no ClusterIssuer, no Boron. They reach the outside
through the shared ENTEI edge, which is why their exposure mode is fixed.

## The schema is the gate

`values.schema.json` is load-bearing — it makes the invalid states
_unrepresentable_ rather than merely discouraged. It enforces:

- `profile` is one of the seven; an eighth name fails.
- `profile` and `serviceTree.landscape` must name the same landscape.
- `exposure.class` ∈ `human | api | oidc-public`. `admin`, `management`,
  `dependency`, and `public-callback` are absent from the enum.
- `exposure.mode` is fixed per profile: `boron-direct` ⇔ lapras;
  `local-loopback` on ditto/rotom/absol; `entei-service-sync` on the hosted
  three. A **hosted Boron claim cannot be expressed.**
- `exposure.callbackMode` is `const: "none"` (§11.1 — the frontend never
  publishes a per-preview callback endpoint, even on plusle/minun where the
  landscape supports Mercury routing).
- `serviceTree` has `additionalProperties: false` and no `instance`.
- `runtime.env` keys must match `^ATOMI_[A-Z0-9_]*$`, and three known secret
  keys are explicitly forbidden there.
- `service.type` is `const: "ClusterIP"`.
- `podSecurityContext.runAsNonRoot` is `const: true`;
  `containerSecurityContext.allowPrivilegeEscalation` is `const: false` and
  `readOnlyRootFilesystem` is `const: true`.
- Non-local profiles must pin `image.digest` matching `^sha256:[a-f0-9]{64}$`.

> Helm validates schemas with Go's RE2 engine. Patterns here must avoid
> lookahead/lookbehind — RE2 has neither.

## Proving the gate holds

`profiles/rejected-hosted-boron.yaml` is a **negative fixture**: it must fail.
It claims a hosted profile (`eevee`) on the Boron rail, with a `public-callback`
class and Mercury callback routing — three separately unrepresentable things.

```bash
helm template t infra/garden_app_chart -f infra/garden_app_chart/profiles/rejected-hosted-boron.yaml
# exits 1: class not in enum, callbackMode must be "none", allOf mode rules fail
```

Other cases that must fail, all verified: an eighth profile name;
`serviceTree.instance`; `readOnlyRootFilesystem: false`; `runAsNonRoot: false`;
`service.type: LoadBalancer`; a secret key inside `runtime.env`; a hosted
profile with an empty digest.

## The image

`infra/Dockerfile.garden` builds the immutable Next.js `output: 'standalone'` image.
Standalone output ships **neither `public/` nor `.next/static/`**, so both are
copied in explicitly alongside `config/`; the container boots
`.next/standalone/server.js` as nonroot uid/gid `1001`.

```bash
docker build -f infra/Dockerfile.garden -t diene-nextjs-frontend:local .
```

The chart mounts emptyDirs at `/tmp` and `scratch.cachePath` so
`readOnlyRootFilesystem: true` holds at runtime.

## Verify

```bash
helm lint infra/garden_app_chart
for p in lapras ditto rotom absol eevee plusle minun; do
  helm template t infra/garden_app_chart -f "infra/garden_app_chart/profiles/$p.yaml" \
    | kubeconform -strict -summary -kubernetes-version 1.31.0 -
done
```
