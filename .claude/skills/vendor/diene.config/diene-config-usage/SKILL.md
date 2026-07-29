---
name: diene-config-usage
description: Use when consuming @atomicloud/diene.config — registering config blocks, running the 4-tier loader, the build-time (/build-time) variant, env-override rules, or faking config in tests via /test-helper.
---

# Diene Config usage

Use this skill when loading configuration with `@atomicloud/diene.config`,
wiring the build-time variant, or faking config sources in tests. Import only
the package root, `/build-time`, or `/test-helper` — never copy the
implementation or reach into `src/`/`dist/`.

Read the authoritative
[config standard](https://github.com/AtomiCloud/diene.bun-config/blob/main/docs/standards/config/index.md).

## Load configuration (runtime)

1. Each engine/library exports its own zod block schema; a service composes them
   into a registry: `ConfigRegistry.create().register('server', ServerSchema)...`.
2. Point a `YamlConfigSource` at the config directory and load — the loader runs
   the 4-tier merge (base YAML → landscape overlay → build-time → runtime env
   LAST) and validates the FINAL layer only, fail-fast.
3. Read typed slices: `config('server')`, `config.get('server')`, `config.all()`.
   Use `loader.loadResult()` for the `Result`-returning (railway) variant.

See `assets/consumer.ts` (ESM) and `assets/consumer.cjs` (CJS) for copyable
package-boundary examples.

## The dimension matrix — `/build-time` vs the runtime loader

Build-time is a dimension for ALL app types: shared/client/server crossed with
build-time/runtime.

- **Runtime loader** (package root): SSR/server code, keeps runtime secrets.
- **`/build-time`** (`buildTimeValueMap`): the inlineable client/build-time
  subset frozen into a bundle via a DefinePlugin-style injection (nextjs owns the
  DefinePlugin wiring; this lib owns the value map). Runtime env still wins where
  present. Fully-static frontends carry ZERO runtime env, hence no runtime
  secrets. Build-time SECRETS (e.g. a source-map upload key) are consumed by the
  build step only and never persisted into the artifact.

## Env-override contract (must follow)

- `prefix` is REQUIRED — there is no baked default (`ATOMI_` is only an example).
- `__` separates nesting; a snake segment matches snake/Pascal/camel/kebab keys.
- Lists use INDEXED KEYS (`FOO__0`, `FOO__1`) — **never** JSON-in-env, never
  comma encoding.
- **Never** hand-roll `Number(process.env.X)` — route through the loader; number
  coercion is zod's job (M31).
- A **blank** env value means UNSET (M33) — it is dropped, not written as `''`.
- Secrets are blank in YAML and injected at runtime via Infisical.

## Testing (`/test-helper`)

`@atomicloud/diene.config/test-helper` ships `InMemoryConfigSource` (plain-object
tier providers — no files, no `process.env` mutation), `stubConfig` (a validated
config from in-memory tiers), `withLandscape` (landscape fake), and the
`expectValid`/`expectInvalid` asserters. Run one behavioral suite against BOTH
`YamlConfigSource` and `InMemoryConfigSource` for real-vs-fake parity. See
`assets/test-helper.md`.
