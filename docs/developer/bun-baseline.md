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
- `pls test`, `pls test:unit`, `pls test:int`, and `pls test:sit` run the test
  tiers without coverage; SIT drives the freshly compiled binary.
- `pls test:coverage`, `pls test:unit:coverage`,
  `pls test:int:coverage`, and `pls test:sit:coverage` write scoped LCOV
  artifacts. SIT coverage uses the in-process driver only.
- `pls test:watch` watches the unit tier.
- `pls build` bundles the `package.json` `bin` entry to `dist/bun-cli.js`.
- `pls compile` emits the three supported standalone binaries under `dist/bin/`.
- `pls deadcode` runs the two non-blocking LLM-review Knip configurations.
- `pls run -- <args>` executes the source entry point.
- `pls preview -- <args>` compiles and executes this host's standalone binary.
- `pls up` and `pls down` manage the sample Redis used for interactive CLI runs.
- `pls docker:build` and `pls docker:run` build and run the Bun image.

There is no `pls dev` surface. Integration and SIT own isolated Redis containers;
`up`/`down` exist only for interactive sample commands.

## Quality gates

Biome is lint-only; treefmt owns formatting. TypeScript uses strict no-emit
typechecking. Knip runs twice as blocking hooks: the repository view includes
tests, while the production view starts at `bin/bun-cli.ts` and catches files
used only by tests. The LLM Knip variants are review-only and never suppress
strict findings.

## Test and coverage tiers

- Unit tests live under `tests/unit/` and cover only `src/lib/**`.
- Integration tests live under `tests/integration/`, use Testcontainers Redis,
  and cover only `src/adapters/**`.
- SIT lives under `tests/sit/`: binary mode is black-box, while in-process mode
  records the full-system `coverage/sit/lcov.info` ledger.
- Both CI entry points require an LCOV artifact, reject paths outside their
  tier ledger, and require every ledger line to be hit.
- Codecov is informational and uploads the independent `unit` and `int` flags
  with carryforward enabled.

Tests use `bun:test`, `describe`/`it`, AAA comments, and `should` assertions.
Container images are version-pinned without digests.

## Build and runtime

The local build and CI build share `scripts/local/build.sh`. The Dockerfile
compiles in a version-pinned `oven/bun` stage and copies only the binary into
`gcr.io/distroless/cc-debian12:nonroot`. `REDIS_HOST` and `REDIS_PORT` select
the Redis endpoint and reject blank or invalid overrides.

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

Downstream templates may adapt package identity, coverage thresholds, the
Docker entry point, badges, and the fenced illustrative `src/` plus `tests/`
sample. They should not fork the inherited task, workflow, release, Nix, lint,
or standards machinery. Shared fixes land at the earliest owning branch and
merge down.
