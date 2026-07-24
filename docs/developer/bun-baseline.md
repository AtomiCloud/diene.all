---
id: bun-baseline
title: Releaser Bun Baseline
---

# Releaser Bun baseline

This repository is a materialized Bun/TypeScript CLI product. General
engineering rules remain in `docs/standards/`; this page records the local
toolchain and test boundaries.

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
- `pls build` bundles the `package.json` `bin` entry to `dist/releaser.js`.
- `pls compile` emits `releaser-linux-x64-baseline`,
  `releaser-linux-arm64`, and `releaser-darwin-arm64` under `dist/bin/`.
- `pls deadcode` runs the two non-blocking LLM-review Knip configurations.
- `pls run -- <args>` executes the source entry point.
- `pls preview -- <args>` compiles and executes this host's standalone binary.

There are no sample dependency, `up`/`down`, probe-matrix, or Docker tasks.

## Architecture and quality gates

The composition root is `bin/releaser.ts`. Pure business logic and ports live in
`src/lib`; concrete Git, filesystem, HTTP, process, configuration, and terminal
implementations live in `src/adapters`. TypeScript uses strict no-emit checking,
Biome linting, treefmt formatting, and strict repository/production Knip views.

Unit tests cover the pure library. Integration tests use temporary directories,
scratch Git repositories, local bare remotes, and fake HTTP only. SIT runs the
same user journeys through either the in-process composition seam or the freshly
compiled Linux x64 binary. No test contacts GitHub or publishes an artifact.

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
