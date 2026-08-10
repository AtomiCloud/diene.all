# Configuration

`@atomicloud/diene.config` is the one config-loading engine for the AtomiCloud
TypeScript family (the R14 config contract). It loads YAML layers, deep-merges
them, validates the service-composed root schema, and serves typed slices via
`config(key)`. It is the family's only merger/validator: engine libraries
(auth-engine, otel, api-engine, …) each own and export their own zod block
schema next to the code that reads it — this lib never defines engine block
schemas, it only merges and validates against whatever root schema a service
composes.

Config is immutable per process — there is no watch/reload in v1. Dev iteration
relies on the framework's HMR/restart.

## The 4-tier merge

Layers apply in strict order, each overriding the previous:

1. **base YAML** — the full defaults (`config/config.yaml`), first line
   `# yaml-language-server: $schema=./schema.json`.
2. **sparse landscape overlay** — only the keys that differ for a landscape
   (`config/<landscape>.config.yaml`).
3. **build-time injection** — values frozen into a bundle at build.
4. **runtime env** — applied LAST; wins over every file tier.

Validation is fail-fast at startup and runs on the **final merged layer only** —
intermediate tiers are never validated. A base file may be individually
incomplete as long as the merged result satisfies the root schema.

## Env-override contract

- **`prefix` is REQUIRED and configurable** — there is no baked default in the
  lib. The app/template sets it (for example `ATOMI_`).
- **`__` is the nesting separator.** `ATOMI_SERVER__PORT` targets
  `server.port`.
- **Case- and separator-insensitive key matching.** A snake segment matches
  snake / Pascal / camel / kebab object keys: `SERVER__MAX_RETRIES` matches
  `maxRetries`.
- **Lists use indexed keys** — `FOO__0`, `FOO__1`, … There is NO JSON-in-env and
  NO comma encoding; this is specced family-wide (in YAML too).
- **Number/boolean coercion goes through zod, never a hand-rolled `Number()`**
  (M31). Declare env-overridable numeric fields with `z.coerce.number()`.
- **A blank env value means UNSET** (M33): it is dropped, leaving the file value,
  never written as an empty string.
- **Secrets are blank in YAML** and injected at runtime (Infisical). Since
  secrets only materialize as runtime env, a fully-static frontend carries none.

## Landscape resolution

The host supplies the landscape; this lib never detects it (it does not import
frontend-utils). `resolveLandscape` prefers an explicit landscape, then the
service-tree `app.landscape` field in the base config, then `base` (defaults
only). Landscape names are validated to a safe token.

## The dimension matrix and `/build-time`

Build-time is a dimension for ALL app types: shared / client / server crossed
with build-time / runtime.

- The **runtime loader** (package root) keeps SSR/server-side runtime secrets.
- The **`/build-time` entry** (`buildTimeValueMap`) exposes the inlineable
  client/build-time subset for a DefinePlugin-style static injection. nextjs owns
  the DefinePlugin wiring; this lib owns the value map. Runtime env still wins
  over frozen build-time values.
- **Build-time secrets** (e.g. a Faro source-map upload key,
  `ATOMI_CLIENT__FARO__BUILD__KEY`) are CI-injected during the build, consumed by
  the build step only, and NEVER persisted into the artifact — distinct from
  build-time-inlined client values (which do end up in the bundle) and from
  runtime secrets (server-side, never build-time).

## Public surface

- `ConfigRegistry.create().register(key, schema)` — immutable, typed registry of
  named config blocks. `rootSchema()` composes them into one zod object.
- `ConfigLoader(source, registry, { prefix, landscape })` — runs the merge and
  validates. `load()` throws `ConfigValidationError` on failure; `loadResult()`
  returns a `Result` (railway) instead, dogfooding `@atomicloud/diene.result`.
- `config(key)` / `config.get(key)` / `config.all()` — the typed accessor.
- `YamlConfigSource` — the real `ConfigSource` (base + overlay YAML + env). Fakes
  live in `/test-helper`.
- `generateJsonSchema(registry)` — emit a JSON Schema from the zod registry so a
  config YAML's `$schema` first line points at a GENERATED schema (R14).
- `deepMerge` and the env-coercion helpers live here — this lib is their only
  consumer-facing home (moved out of core-utils).

## TestHelper (`/test-helper`)

`@atomicloud/diene.config/test-helper` ships in-memory tier providers
(`InMemoryConfigSource`), a validated `stubConfig` builder, a `withLandscape`
fake, and the `expectValid`/`expectInvalid` asserters. The fakes feed the SAME
loader as production, so a single behavioral suite proves real-vs-fake parity.
Helper-only dependencies are declared as optional peerDependencies, never regular
dependencies. The meta tier measures coverage over TestHelper code only.
