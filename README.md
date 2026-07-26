# Diene Go e2e test-harness library

<!-- ### go-base-badges -->
<!-- #### source: go-base -->

[![CI](https://github.com/AtomiCloud/diene.go-e2e/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.go-e2e/actions/workflows/ci.yaml)
[![Unit coverage](https://codecov.io/gh/AtomiCloud/diene.go-e2e/branch/main/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.go-e2e)
[![Integration coverage](https://codecov.io/gh/AtomiCloud/diene.go-e2e/branch/main/graph/badge.svg?flag=int)](https://codecov.io/gh/AtomiCloud/diene.go-e2e)
[![Meta coverage](https://codecov.io/gh/AtomiCloud/diene.go-e2e/branch/main/graph/badge.svg?flag=meta)](https://codecov.io/gh/AtomiCloud/diene.go-e2e)
[![Go Reference](https://pkg.go.dev/badge/github.com/AtomiCloud/diene.go-e2e.svg)](https://pkg.go.dev/github.com/AtomiCloud/diene.go-e2e)
[![Commit activity](https://img.shields.io/github/commit-activity/m/AtomiCloud/diene.go-e2e)](https://github.com/AtomiCloud/diene.go-e2e/commits/main)

<!-- ### nix-root -->
<!-- #### source: main -->

Diene's reproducible development environment is managed by Nix. Run `direnv allow` once, then use `pls` tasks from the loaded shell.

<!-- ### workspace -->
<!-- #### source: workspace -->

This repository inherits the all-features workspace baseline: split CI/CD,
secrets, release configuration, validators, standards, and vendored agent-skill
synchronization.

## Commands

- `pls setup` — synchronize installed diene package skills.
- `pls lint` — run every pre-commit gate.
- `pls secret:scan` — scan tracked content for secrets.
- `pls skills:sync` — rebuild `.claude/skills/vendor/` from installed packages.

<!-- ### go-lib -->
<!-- #### source: go-lib -->

## Publishable Go module

`github.com/AtomiCloud/diene.go-e2e` is the Go family's SIT/e2e test harness:
compiled-artifact and in-process SIT drivers that run one journey two ways
against the Garden preview environment, Garden preview-target resolution,
config/env fixtures, and a `testhelper` package that bundles every sibling
TestHelper in the family plus Testcontainers stack glue for DB-adapter
integration tests.

It is **Bruno-free**. Bruno orchestration is a sample-side concern owned by the
service templates, never by this harness.

It consumes all eight published `github.com/AtomiCloud/diene.go-*` siblings
through the public Go proxy — no `replace` directives, no path dependencies —
so its own suites are the family's downstream real-consumption evidence.

```bash
go get github.com/AtomiCloud/diene.go-e2e@latest
```

```go
report, err := e2e.RunJourney(ctx, driver, journey, problems)
```

Packages:

- `lib/e2e` — the `Driver` seam, the compiled-artifact and in-process SIT
  drivers, the journey runner, driver parity comparison, and the harness
  problem catalog.
- `lib/preview` — Garden preview-environment target resolution and the otel,
  auth, api, and infra-preset configuration it implies.
- `lib/fixture` — layered config/env fixtures: base plus landscape overlay plus
  C0-shaped environment, materialized through the `Vfs` seam.
- `adapters/process` — the real `interfaces.Terminal` binding the
  compiled-artifact driver runs on.
- `testhelper` — the family TestHelper bundle, the Testcontainers stack glue,
  scripted drivers, and harness assertions.

Usage patterns live in the shipped usage skill
`skills/diene-go-e2e-usage/SKILL.md`.

<!-- ### go-base-commands -->
<!-- #### source: go-base -->

## Go commands

- `pls build` — build every package in the module.
- `pls typecheck` — compile every source package without running tests.
- `pls test` / `pls test:coverage` — run unit, integration, and active meta tiers.
- `pls deadcode` — run strict whole-repository and production passes plus the LLM-lax report.
- `pls up` / `pls down` — start or stop local Redis (the meta tier boots its own Testcontainers).
- `./scripts/ci/pkg-validate.sh all` — run module-path, vet, API, docs, and example validators.

See the [Go baseline](docs/developer/go-baseline.md) for the language contract and
template-maintenance boundary.
See the [Go library baseline](docs/developer/go-lib-baseline.md) for promotion,
testing, compatibility, and publication policy.

## Standards

- [CI/CD workflows](docs/standards/ci-cd/index.md)
- [conventional commits](docs/standards/conventional-commits/index.md)
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
