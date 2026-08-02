---
id: bun-baseline
title: Bun Baseline
---

# Bun Baseline

`bun-base` is the Bun foundation for `AtomiCloud/diene.bun-base`. It is a
**sibling-template foundation**: sibling templates copy it and adapt a small set
of settings (see [Template maintenance](#template-maintenance)) before formal
CyanPrint template promotion.

Only Bun-specific baseline behavior is documented here. General standards stay
in `docs/standards/`, with TypeScript guidance under each applicable
`languages/typescript.md` path.

## Local commands

New Bun entries:

- `pls test` — all suites, no coverage (unit + int)
- `pls test:unit`, `pls test:int` — one suite, no coverage
- `pls test:coverage`, `pls test:unit:coverage`, `pls test:int:coverage` — with
  per-tier coverage
- `pls test:watch` — unit watch mode
- `pls build`
- `pls run -- <args>` — run `src/index.ts`
- `pls preview -- <args>` — build and run `dist/index.js`
- `pls deadcode`

## Test modes

Two suites are split by Bun config so the fast path stays Docker-free:

- **Unit** (`bunfig.unit.toml`, root `tests/unit`) — pure `src/lib` behaviour.
  No containers; this is the default fast path.
- **Integration** (`bunfig.int.toml`, root `tests/integration`) — exercises the
  `src/adapters` boundary against a throwaway Redis container via Testcontainers.
  Slow and Docker-dependent, so it lives on a dedicated path.

The same `tasks/Taskfile.test.yaml` is imported twice from the root `Taskfile.yaml`
(parameterised by `MODE`/`CONFIG`) as the internal `unit:*` and `int:*` namespaces;
the `test:*` root tasks are thin delegations onto them — there is one test recipe,
not two.

Prettier owns formatting. Biome is lint-only. Biome and Knip are declared in
`package.json`, locked by `bun.lock`, and invoked from `./node_modules/.bin` in
pre-commit.

## Coverage gates

- Unit coverage: `coverage/unit/lcov.info` — the `src/lib` domain ledger, gated
  at 100%.
- Integration coverage: `coverage/int/lcov.info` — the `src/adapters` ledger,
  gated at 100%.
  Each bunfig scopes its ledger via `coveragePathIgnorePatterns` (bun has no
  include mode).
- The local coverage artifact is blocking.
- Codecov upload is non-blocking and split by `unit` / `int` flags.
- `codecov.yml` thresholds are informational by default.

## Build & runtime

- Bun is the application runtime and build target.
- `pls build` (and `scripts/ci/build.sh`) bundle `src/index.ts` to
  `dist/index.js` with `bun build --target bun`.
- Pino emits structured logs and enriches each record with the active trace
  context exposed by `@atomicloud/diene.otel`.
- Redis settings are validated with Zod; blank values are treated as unset.
- `infra/Dockerfile` is a multi-stage Bun image pinned to a Bun version.
- The runtime stage runs as the non-root `bun` user.
- `pls docker:build:main && pls docker:run:main` builds and runs the sample
  executable; it prints the composed sample key by default. When `REDIS_HOST`
  and `REDIS_PORT` are set, the executable uses the Redis adapter to persist and
  read back a sample value.

## External service / compute cost

- Codecov upload runs only in CI and is best-effort.
- Integration tests and Docker image builds require a Docker runtime.
- Unit, integration, build, Docker, and Helm are separate CI jobs.

## Template maintenance

`bun-base` is consumed by sibling templates before formal template promotion.
Keep CyanPrint-managed/shared scaffold edits additive. Settings a downstream
template is expected to adapt:

- **Package metadata** — `package.json` `name`/`description`.
- **Coverage thresholds** — `bunfig.*.toml` and `codecov.yml`.
- **Docker runtime entrypoint** — `infra/Dockerfile` `ENTRYPOINT`.
- **Badges / template promotion** — the `AtomiCloud/diene.bun-base` paths in
  `README.md` badges are rewritten on promotion.
- **Sample source/tests** — `src/lib`, `src/adapters`, `src/index.ts`, and the
  matching `tests/` suites are illustrative and replaced per service.

The Helm and secret task files (`tasks/Taskfile.helm.yaml`,
`tasks/Taskfile.secret.yaml`) are intentionally left untouched by the Bun
baseline — there is no direct Bun dependency on them.

Merge ownership stays manual: CI is driven to green, but the actual merge is a
human action.
