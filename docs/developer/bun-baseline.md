---
id: bun-baseline
title: Bun Baseline
---

# Bun Baseline

`bun-base` is the Bun and TypeScript foundation inherited by the Bun sample
family. This page documents only language-layer behavior; general engineering
rules remain in `docs/standards/`.

## Local commands

- `pls setup` installs the locked Bun dependencies after synchronizing vendored
  package skills.
- `pls lint` runs every generated pre-commit hook.
- `pls test`, `pls test:unit`, and `pls test:int` run the test tiers without
  coverage.
- `pls test:coverage`, `pls test:unit:coverage`, and
  `pls test:int:coverage` write scoped LCOV artifacts.
- `pls test:watch` watches the unit tier.
- `pls build` bundles `src/index.ts` to `dist/index.js`.
- `pls deadcode` runs the two non-blocking LLM-review Knip configurations.
- `pls run -- <args>` executes the source entry point.
- `pls preview -- <args>` rebuilds and executes the bundled artifact.

There is no `pls dev`, `pls up`, or `pls down` surface in this base. Hot reload
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

The local build and CI build share `scripts/local/build.sh`. The sample prints
a composed key by default; `REDIS_HOST` plus `REDIS_PORT` enable a Redis round
trip.

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

## Template maintenance boundary

Downstream templates may adapt package identity, coverage thresholds, badges,
and the fenced illustrative `src/` plus `tests/` sample. They should not fork
the inherited task, workflow, release, Nix, lint,
or standards machinery. Shared fixes land at the earliest owning branch and
merge down.
