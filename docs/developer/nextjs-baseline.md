# Next.js Baseline

The frontend counterpart to [the Bun baseline](./bun-baseline.md): this page
documents ONLY the Next.js layer of this template — what the template owns, what
the published libraries own, the App-Router-on-Workers caveats, and the two
deploy rails. General engineering rules stay in `docs/standards/`, and the UI
quality rules stay in [frontend UX](../standards/frontend-ux/index.md).

This template inherits every Bun gate (unit, integration, typecheck, lint,
coverage ledgers, dead code twice, build, release, CI wiring, binary smoke) from
the Bun base. Read the Bun baseline first; nothing there is repeated here.

---

## Template maintenance boundary

A downstream product built from this template MAY adapt:

- package identity, branding, and every value in `config/*.yaml`;
- the illustrative `src/` and `tests/` sample — pages, components, the sample
  domain, the locale message files;
- the identity layer: `docs/domain/identity.md`, `src/lib/tokens/index.ts`, the
  token block in `src/styles/globals.css`, and the branded loader;
- coverage thresholds and badges, per the Bun baseline;
- the landscape matrix and deploy targets in `wrangler.toml` and the CI upload
  script.

A downstream product should NOT fork:

- the inherited task, workflow, release, Nix, lint, or standards machinery;
- the validators under `scripts/validate/`;
- the spine modules — see the next section. Shared fixes land at the earliest
  owning branch and merge down.

### Spine modules are CONSUMED, never copied

The portable spine lives in published packages and is consumed from npm. Copying
library source into `src/` is forbidden: a local fork silently diverges and the
version train stops being one consistent lib set.

| Concern                                                  | Package                                                                                 |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| Result and monads                                        | `@atomicloud/diene.result`                                                              |
| Problem contract and catalog types                       | `@atomicloud/diene.problems`                                                            |
| Config load, merge, validate, build-time tier            | `@atomicloud/diene.config`                                                              |
| Generated API client mapping to `Result<T, Problem>`     | `@atomicloud/diene.api-engine`                                                          |
| Auth, login redirect, home claim, per-backend phases     | `@atomicloud/diene.auth-engine`                                                         |
| Temporal-class to C0 wire codecs                         | `@atomicloud/diene.core-utils`                                                          |
| OpenTelemetry alignment                                  | `@atomicloud/diene.otel`                                                                |
| Module registry, landscape, content, theme               | `@atomicloud/diene.frontend-utils` (`/module`, `/landscape`, `/content`, `/theme`)      |
| URL-state controller, draft persistence, a11y, discovery | `@atomicloud/diene.frontend-utils` (`/urlstate`, `/persistence`, `/a11y`, `/discovery`) |

What the template legitimately owns on top of those: the tri-layer glue
(`src/adapters/atomi/**` DI wiring and providers), the thin hooks that bind a
library controller to React (`src/adapters/hooks/**`), the rule-defaulting
components (`src/components/**`), the pure domain under `src/lib/**`, and the
App Router routes.

Config block schemas are ENGINE-OWNED: each engine exports the schema for the
block it reads, and this app composes its root schema by importing those blocks
one line per engine. The config library is only the merger and validator.

---

## Layer discipline

- `src/lib/**` is pure logic with 100% unit coverage. No I/O, no React, no
  framework imports.
- `src/adapters/**` is every impure edge: auth, config, HTTP clients, storage,
  the module registry, the React bindings.
- Pages are PURE RENDERERS — `scripts/validate/pure-renderer.ts` is a blocking
  gate. A page reads params, sets the locale, reads translations, and mounts
  components. It never imports a service.
- The domain layer uses Temporal-class types; the wire uses C0 standardized
  string formats; codecs convert between them. This applies to the frontend
  exactly as it does to a backend.

---

## App-Router-on-Workers caveats

Ten rules govern the Workers rail. They are template law, not advice.

1. **Worker size budget** — 3 MiB compressed on the free plan, 10 MiB on paid.
   Watch bundle size on every dependency addition.
2. **Node runtime ONLY** — `export const runtime = "edge"` is FORBIDDEN; it
   breaks the OpenNext adapter. `scripts/validate/forbidden-runtime.ts` enforces
   it statically.
3. **Middleware stays edge-style only.**
4. **ISR bindings are pre-wired** — R2 incremental cache, Durable Object queue,
   D1 tag cache. Never KV for ISR. See `open-next.config.ts` and
   `wrangler.toml`.
5. **`next/image` goes through the Cloudflare Images binding** — the default
   optimizer route does not exist on Workers.
6. **PPR and `use cache` are OFF by default** — adapter support is immature.
7. **DB clients are created per request** — no global connection reuse across
   requests on isolates.
8. **Test against real workerd** via `opennextjs-cloudflare preview`, never
   `next dev` alone.
9. **Source maps upload via `@grafana/faro-webpack-plugin`**, invoked inline
   from the `next.config.ts` webpack hook during the OpenNext build. The upload
   key is a BUILD-TIME SECRET: injected right before the build, consumed by the
   plugin, never persisted into the artifact.
10. **Adapter-lag awareness** — assume an experimental Next feature is
    unsupported until it is verified against `opennextjs-cloudflare`.

The optional Garden rail runs the standard Node standalone server and has no
workerd or ISR binding dependency, so caveats 1, 2, 4, 5, 6, and 8 do not
constrain it.

---

## Two deploy rails

Both rails boot the SAME build (`output: 'standalone'` in `next.config.ts`).
Landscape is a RUNTIME value on both: the server tells the client, and the
client-safe subset ships as an SSR-injected payload. The browser never detects
its own landscape.

### Rail 1 — OpenNext to Cloudflare Workers (production)

- `@opennextjs/cloudflare` builds the Worker artifact; `wrangler.toml` declares
  the assets, ISR, and Images bindings.
- ONE artifact promotes through `pichu`, `pikachu`, and `raichu` by swapping the
  environment binding — never rebuilt per stage.
- CI uploads tagged Worker VERSIONS for controller promotion and never deploys
  directly (`scripts/validate/deploy-policy.ts`).
- A standby build ships on every release to a plain repointable CNAME, with a
  weekly synthetic probe, as the outage posture.

### Rail 2 — Garden standalone chart (optional, in-cluster)

- An immutable Node image boots `.next/standalone/server.js` as nonroot with
  `public/` and `.next/static/` copied in — the standalone output does not
  include them by default.
- The chart owns a narrow object set only: one Deployment plus one ClusterIP
  Service. It ships no Gateway, ListenerSet, HTTPRoute, Certificate, Boron,
  kgateway, cert-manager, or callback-tunnel resources; those belong to Garden
  and the selected exposure owner.
- It is disabled by default and enabled by the Garden profile, participating in
  all seven workload profiles. Public-callback membership is invalid for a
  frontend chart.
- Runtime server config supplies landscape, backend endpoints, and issuer and
  auth values; Kubernetes Secrets stay server-only and no runtime secret reaches
  the browser bundle.

Playwright journeys run against the real standalone server — the same artifact
the Garden rail boots — which is why `playwright.config.ts` starts
`node .next/standalone/server.js` rather than `next dev`. The workerd preview
smoke covers the Workers runtime separately.

---

## Frontend-specific quality surface

Beyond the inherited Bun gates:

| Validator                               | Enforces                                               |
| --------------------------------------- | ------------------------------------------------------ |
| `scripts/validate/pure-renderer.ts`     | Pages import no services                               |
| `scripts/validate/forbidden-runtime.ts` | No `runtime = "edge"` anywhere                         |
| `scripts/validate/i18n-keys.ts`         | Every locale carries every required next-intl key      |
| `scripts/validate/rebrand-static.ts`    | Branding, SEO, and SSO values stay config-driven (R21) |
| `scripts/validate/wrangler-config.ts`   | Deployment configuration parses and validates          |
| `scripts/validate/deploy-policy.ts`     | CI uploads versions and never deploys directly         |
| `scripts/validate/pwa-manifest.ts`      | Manifest and service-worker metadata validate          |

There are NO golden-image or screenshot gates. Visual quality is reviewed through
the vision loop; the only browser-side layout assertion is the non-pixel overflow
check in `tests/e2e/resize-fluid.spec.ts`.

---

## Related standards

- [Frontend UX](../standards/frontend-ux/index.md) — the timeless UI checklist,
  plus [the five patterns](../standards/frontend-ux/patterns.md).
- [Frontend UI trend](../standards/frontend-ui-trend/index.md) — the dated visual
  pick.
- [Identity](../domain/identity.md) — the mandatory per-app identity scaffold.
- [Faro frontend variant](../standards/observability/faro.md) — frontend
  observability initialization.
- [Bun baseline](./bun-baseline.md) — the inherited language layer.
