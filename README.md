# Diene Go consumer

<!-- ### go-base-badges -->
<!-- #### source: go-base -->

[![CI](https://github.com/AtomiCloud/diene.go-consumer/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.go-consumer/actions/workflows/ci.yaml)
[![Unit coverage](https://codecov.io/gh/AtomiCloud/diene.go-consumer/branch/main/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.go-consumer)
[![Integration coverage](https://codecov.io/gh/AtomiCloud/diene.go-consumer/branch/main/graph/badge.svg?flag=int)](https://codecov.io/gh/AtomiCloud/diene.go-consumer)
[![Commit activity](https://img.shields.io/github/commit-activity/m/AtomiCloud/diene.go-consumer)](https://github.com/AtomiCloud/diene.go-consumer/commits/main)

<!-- ### nix-root -->
<!-- #### source: main -->

Diene's reproducible development environment is managed by Nix. Run `direnv allow` once, then use `pls` tasks from the loaded shell.

<!-- ### workspace -->
<!-- #### source: workspace -->

This repository inherits the all-features workspace baseline: split CI/CD, Docker,
Helm, secrets, release configuration, validators, standards, and vendored agent-skill
synchronization.

## Commands

- `pls setup` — synchronize installed diene package skills.
- `pls lint` — run every pre-commit gate.
- `pls docker:build` — build the local Go image.
- `pls helm:lint` / `pls helm:template` — validate or render the root chart.
- `pls secret:scan` — scan tracked content for secrets.
- `pls skills:sync` — rebuild `.claude/skills/vendor/` from installed packages.

<!-- ### go-base-commands -->
<!-- #### source: go-base -->

## Go commands

- `pls build` — create `dist/go-consumer`.
- `pls typecheck` — compile every source package without running tests.
- `pls test` / `pls test:coverage` — run both tiers normally or with scoped ledgers.
- `pls deadcode` — run strict whole-repository and production passes plus the LLM-lax report.

See the [Go baseline](docs/developer/go-baseline.md) for the language contract and
template-maintenance boundary.

<!-- ### go-consumer-commands -->
<!-- #### source: go-consumer -->

## Go consumer commands

- `pls dev` — run the worker against the local dependency stack.
- `pls run -- worker` / `pls run -- db-init` / `pls run -- health` — execute from source.
- `pls preview -- worker` — execute the compiled artifact.
- `pls up` / `pls down` — start or stop Postgres, Redis, MinIO, and the telemetry backends.
- `pls test:sit` — run the journeys through the compiled binary.
- `pls test:sit:parity` — run the same journeys through both drivers and compare them.
- `pls schema:gen` — regenerate `schemas/go-consumer.schema.json`.
- `pls problems:export` — export the Problem catalog for the primordial chart.

See the [Go consumer delta](docs/developer/go-consumer.md) for the worker/db-init/health
composition, the configuration contract, and the two-chart model.

## Standards

- [CI/CD workflows](docs/standards/ci-cd/index.md)
- [conventional commits](docs/standards/conventional-commits/index.md)
- [Docker build and publishing](docs/standards/docker/index.md)
- [Helm charts and publishing](docs/standards/helm/index.md)
- [Infisical and secrets](docs/standards/infisical/index.md)
- [linting and pre-commit](docs/standards/linting/index.md)
- [Nix flakes and development shells](docs/standards/nix/index.md)
- [release automation](docs/standards/semantic-release/index.md)
- [service-tree identity](docs/standards/service-tree/index.md)
- [shell scripts](docs/standards/shell-scripts/index.md)
- [Taskfile conventions](docs/standards/taskfile/index.md)

<!-- ### shared -->
<!-- #### source: shared -->

## Shared standards

- [Authorization](docs/standards/authorization/index.md)
- [Contributor documentation](docs/standards/contributor-docs/index.md)
- [Date and time](docs/standards/datetime/index.md)
- [Domain-driven design](docs/standards/domain-driven-design/index.md)
- [Functional practices](docs/standards/functional-practices/index.md)
- [Software design philosophy](docs/standards/software-design-philosophy/index.md)
- [SOLID principles](docs/standards/solid-principles/index.md)
- [Stateless OOP and dependency injection](docs/standards/stateless-oop-di/index.md)
- [Testing](docs/standards/testing/index.md)
- [Three-layer architecture](docs/standards/three-layer-architecture/index.md)
- [Utility libraries](docs/standards/utilities/index.md)
- [Data validation](docs/standards/validation/index.md)

Domain-specific documentation belongs under [docs/domain/](docs/domain/README.md).
The `docs/standards/contracts/` location is reserved for the separately owned C0
contracts standard.

<!-- ### go-base-language-standards -->
<!-- #### source: go-base -->

## Go language variants

- [Date and time](docs/standards/datetime/languages/go.md)
- [Domain-driven design](docs/standards/domain-driven-design/languages/go.md)
- [Functional practices](docs/standards/functional-practices/languages/go.md)
- [SOLID principles](docs/standards/solid-principles/languages/go.md)
- [Stateless OOP and dependency injection](docs/standards/stateless-oop-di/languages/go.md)
- [Testing](docs/standards/testing/languages/go.md)
- [Utilities](docs/standards/utilities/languages/go.md)
- [Validation](docs/standards/validation/languages/go.md)
