---
id: bun-baseline
title: Bun Baseline
---

# Bun Baseline

`bun-base` is the Bun and TypeScript foundation inherited by the Bun sample
family. This page documents only language-layer behavior; general engineering
rules remain in `docs/standards/`.

## Local commands

- `task setup` installs the locked Bun dependencies after synchronizing vendored
  package skills.
- `task lint` runs every generated pre-commit hook.
- `task test`, `task test:unit`, and `task test:int` run the test tiers without
  coverage.
- `task test:coverage`, `task test:unit:coverage`, and
  `task test:int:coverage` write scoped LCOV artifacts.
- `task test:watch` watches the unit tier.
- `task build` bundles `src/index.ts` to `dist/index.js`.
- `task deadcode` runs the two non-blocking LLM-review Knip configurations.
- `task run -- <args>` executes the source entry point.
- `task preview -- <args>` rebuilds and executes the bundled artifact.
- `task docker:build` and `task docker:run` build and run the Bun image.
- `task helm:lint` and `task helm:template` retain the inherited Helm axis.

There is no `task dev`, `task up`, or `task down` surface in this base. Hot reload
belongs to runnable descendants, and the integration tier owns its Redis
dependency through Testcontainers.

## Quality gates

Biome is lint-only; treefmt owns formatting. TypeScript uses strict no-emit
typechecking. Knip runs twice as blocking hooks: the repository view includes
tests, while the production view starts at `src/index.ts` and catches files
used only by tests. The LLM Knip variants are review-only and never suppress
strict findings.

## Test and coverage tiers

- Unit tests live under `tests/unit/` and cover only `src/lib/**`.
- Integration tests live under `tests/integration/`, use Testcontainers Redis,
  and cover only `src/adapters/**`.
- Both CI entry points require an LCOV artifact, reject paths outside their
  tier ledger, and require every ledger line to be hit.
- Codecov is informational and uploads the independent `unit` and `int` flags
  with carryforward enabled.

Tests use `bun:test`, `describe`/`it`, AAA comments, and `should` assertions.
Container images are version-pinned without digests.

## Build and runtime

The local build and CI build share `scripts/local/build.sh`. The Dockerfile
uses version-pinned `oven/bun` build and runtime stages, installs from the
frozen lockfile, bundles the sample, and runs as the unprivileged `bun` user.
The sample prints a composed key by default; `REDIS_HOST` plus `REDIS_PORT`
enable a Redis round trip.

Application descendants use pino JSON logging with trace-context injection
from `@atomicloud/diene.otel`. That application logging layer is intentionally
not duplicated in this toolchain sample before the shared library is consumed.

## TypeScript standards

Read the TypeScript variants alongside their shared standards:

- [date/time](../standards/datetime/languages/typescript.md)
- [domain-driven design](../standards/domain-driven-design/languages/typescript.md)
- [functional practices](../standards/functional-practices/languages/typescript.md)
- [SOLID principles](../standards/solid-principles/languages/typescript.md)
- [stateless OOP and dependency injection](../standards/stateless-oop-di/languages/typescript.md)
- [testing](../standards/testing/languages/typescript.md)
- [utilities](../standards/utilities/languages/typescript.md)
- [validation](../standards/validation/languages/typescript.md)

## External service / compute cost

- Codecov upload runs only in CI and is best-effort.
- Integration tests and Docker image builds require a Docker runtime.
- Unit, integration, build, Docker, and Helm are separate CI jobs.

## Template maintenance boundary

Downstream templates may adapt package identity, coverage thresholds, the
Docker entry point, badges, and the fenced illustrative `src/` plus `tests/`
sample. They should not fork the inherited task, workflow, release, Nix, lint,
or standards machinery. Shared fixes land at the earliest owning branch and
merge down.
