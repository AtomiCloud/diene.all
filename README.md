# Diene Go interfaces library

<!-- ### go-base-badges -->
<!-- #### source: go-base -->

[![CI](https://github.com/AtomiCloud/diene.go-interfaces/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.go-interfaces/actions/workflows/ci.yaml)
[![Unit coverage](https://codecov.io/gh/AtomiCloud/diene.go-interfaces/branch/main/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.go-interfaces)
[![Integration coverage](https://codecov.io/gh/AtomiCloud/diene.go-interfaces/branch/main/graph/badge.svg?flag=int)](https://codecov.io/gh/AtomiCloud/diene.go-interfaces)
[![Meta coverage](https://codecov.io/gh/AtomiCloud/diene.go-interfaces/branch/main/graph/badge.svg?flag=meta)](https://codecov.io/gh/AtomiCloud/diene.go-interfaces)
[![Go Reference](https://pkg.go.dev/badge/github.com/AtomiCloud/diene.go-interfaces.svg)](https://pkg.go.dev/github.com/AtomiCloud/diene.go-interfaces)
[![Commit activity](https://img.shields.io/github/commit-activity/m/AtomiCloud/diene.go-interfaces)](https://github.com/AtomiCloud/diene.go-interfaces/commits/main)

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

`github.com/AtomiCloud/diene.go-interfaces` is the Go family's
implementation-free seam library. It defines portable system, virtual
filesystem, terminal, logging, and metrics contracts, with ordinary `(T, error)`
failure slots. Implementations return problem-typed errors from
`diene.go-errors-problems`; this module ships deterministic in-memory mocks in
its consumer-facing `testhelper` package.

```bash
go get github.com/AtomiCloud/diene.go-interfaces@latest
```

```go
system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
now, err := system.NowUTC()
```

<!-- ### go-base-commands -->
<!-- #### source: go-base -->

## Go commands

- `pls build` — build every package in the module.
- `pls typecheck` — compile every source package without running tests.
- `pls test` / `pls test:coverage` — run unit, integration, and active meta tiers.
- `pls deadcode` — run strict whole-repository and production passes plus the LLM-lax report.
- `pls up` / `pls down` — start or stop local Redis.
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
