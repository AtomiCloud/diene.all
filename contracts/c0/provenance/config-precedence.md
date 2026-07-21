### §3 Config precedence

- Layering: base YAML (full defaults) → sparse landscape overlay → **env override
  LAST**; validation fail-fast at startup on the FINAL merged layer only.
- Env contract: prefix is a **CONFIGURABLE option** the config lib exposes, set per
  app (no family-wide hardcoded prefix — the app/template supplies it, naturally
  sourced from the composed config's service-tree/`app:` block); `__` = nesting
  separator; key matching **case-insensitive across kebab/snake/camel/pascal** (one
  canonical normalization rule spec'd; keys authored in host-language casing).
  Examples below show `ATOMI_` as the prefix CONFIGURED for that app, not a fixed
  value.
- Env-var LIST encoding = **indexed keys** (`FOO__0`, `FOO__1`, …), spec'd for all four
  languages: dotnet configuration binder handles it natively; go/bun/dart loaders
  implement indexed collection. NO JSON-in-env, NO comma encoding — replaces tin's
  former JSON-string workaround.
- Config schema ownership: each engine lib (auth-engine, otel, api-engine, …) exports
  its OWN config block schema next to the code that reads it; `standard-config` holds
  ONLY infra preset schemas (postgres/cache/kv/storage + Testcontainers helpers). The
  CONFIG lib is the sole merger/validator — loads YAML layers, deep-merges, validates
  the service-composed root schema, serves typed slices. Services compose their root
  schema by importing blocks (one line per engine + presets + own keys); C0 freezes
  block key names family-wide, the unified view is documentation only. dart gets NO
  standard-config lib — engine-owned schemas make dart symmetric.
- **Preset-shape parity is explicitly on the freeze list**: `standard-config`'s
  infra preset shapes (postgres/cache/kv/storage blocks) are part of C0's
  family-wide config freeze, so bun/dotnet(/go) standard-config libs match
  key-for-key — already a hard gate for libs (dotnet-family: libs cannot finalize
  public config types before C0 lands).
- Secret-and-config unification: secrets are ordinary config keys, blank-in-yaml,
  injected per landscape (Infisical) through the SAME env override path.
- Build-time vs runtime semantics: build-time tier is available to ALL app types, not
  just frontends (base→landscape→build→runtime, 4-tier everywhere); backend build-time
  keys are the exception not the rule, frontends use it routinely (argon
  DefinePlugin/dart-define); spec which keys may be build-time-frozen and how runtime
  injection overrides.
- NO-RUNTIME-ENV frontend mode: fully static deployments carry ZERO runtime env vars —
  secrets only ever materialize as runtime env, so a no-runtime-env static app carries
  NO secrets at runtime by construction; this is a recognized, named config mode, not
  an edge case.
- BUILD-TIME SECRETS (a distinct config class): CI-injected during the build (e.g.
  faro source-map upload key at Layer C), consumed by the build step only, NEVER
  persisted into the artifact/bundle; distinct from runtime secrets (the
  secret-and-config unification above stays runtime-only). Verify the faro shape
  against alcohol's actual wiring (GitHub) before finalizing this section — do not
  spec from memory.
- **Landscape is IDENTITY, never a secret** (hybrid-by-shape across frontend types):
  client-side, landscape always arrives via bake or server-injection — NEVER as
  a client-fetched env var. Per-shape source table:
  - nextjs (OpenNext/Cloudflare Workers): **RUNTIME**, via Worker env binding; server
    tells client — landscape + landscape-derived config ship as an SSR-injected
    payload, browser never detects; one build artifact promotes through all stages,
    per-landscape = different bindings, preview envs = same build + preview binding.
  - Fully-static web frontends: **BUILD-TIME**, baked via the no-runtime-env
    `/build-time` entry (no server, no runtime secrets); promotion = rebuild per
    landscape (Kargo promotes a git ref).
  - flutter/mobile: **BUILD-TIME**, per store track via `--dart-define` — the track
    IS the landscape; optional DEBUG-ONLY landscape switcher in internal builds.
  - frontend-utils landscape module is an ACCESSOR not a detector: one `landscape()`
    API fed by binding (nextjs) / baked constant (static) / dart-define (flutter);
    app code never knows the source. Hostname sniffing is DEAD — no host-based
    detection anywhere.
- Every config YAML: **generated `$schema` pointer as FIRST line** (zod /
  typescript-json-schema / NJsonSchema); schema drift = CI red.
- `config/dev.yaml` = the single local-dev control file, read by scripts via `yq`.
- Service-tree `app:` block (landscape/platform/service/module/version) mandatory;
  connection-pool names UPPERCASE.
