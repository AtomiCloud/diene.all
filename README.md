# Diene Go auth-engine library

<!-- ### go-base-badges -->
<!-- #### source: go-base -->

[![CI](https://github.com/AtomiCloud/diene.go-auth-engine/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.go-auth-engine/actions/workflows/ci.yaml)
[![Unit coverage](https://codecov.io/gh/AtomiCloud/diene.go-auth-engine/branch/main/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.go-auth-engine)
[![Integration coverage](https://codecov.io/gh/AtomiCloud/diene.go-auth-engine/branch/main/graph/badge.svg?flag=int)](https://codecov.io/gh/AtomiCloud/diene.go-auth-engine)
[![Meta coverage](https://codecov.io/gh/AtomiCloud/diene.go-auth-engine/branch/main/graph/badge.svg?flag=meta)](https://codecov.io/gh/AtomiCloud/diene.go-auth-engine)
[![Go Reference](https://pkg.go.dev/badge/github.com/AtomiCloud/diene.go-auth-engine.svg)](https://pkg.go.dev/github.com/AtomiCloud/diene.go-auth-engine)
[![Commit activity](https://img.shields.io/github/commit-activity/m/AtomiCloud/diene.go-auth-engine)](https://github.com/AtomiCloud/diene.go-auth-engine/commits/main)

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

`github.com/AtomiCloud/diene.go-auth-engine` is the Go family's server-side auth
engine: JWT/JWKS validation against a baked OIDC issuer, the Logto adapter,
per-resource access tokens over the `resourceTree` model, machine-to-machine
client-credential flows, deferred deep-link login mint/redeem, the `OnboardSync`
per-backend onboarding phase machine, and the family nullable-userId ownership
authorization pattern — all problem-typed through
`github.com/AtomiCloud/diene.go-errors-problems` and shipped with a
consumer-facing `testhelper` package.

```bash
go get github.com/AtomiCloud/diene.go-auth-engine@latest
```

```go
principal, err := validator.Validate(ctx, bearer)
if err != nil {
	return err
}
if err := guard.SubOrAny(principal, query.UserID, authengine.ClaimRoles, "admin"); err != nil {
	return err
}
```

Packages:

- `lib/authengine` — validation, principal mapping, resource tree and token
  cache, retrievers, refresh rotation, ownership guard, named claim policies,
  and the engine-owned config block.
- `lib/logto` — the Logto adapter behind the provider seam (OIDC discovery,
  remote JWKS, token endpoint, one-time tokens, Management API claim
  write-back).
- `lib/deferred` — deferred deep-link login: nonce mint/exchange plus the
  Android Install Referrer and iOS clipboard carrier builders.
- `lib/onboard` — `OnboardSync`: claims-first per-backend onboarding phase
  machine and the pre-onboarding home-landscape selector.
- `testhelper` — fake IdP/JWKS, fake provider, in-memory stores, per-backend
  onboarding fakes, and Problem-shaped auth assertions.

Engine concepts (resourceTree, deferred deep-link login, the onboarding phase
machine, and the ownership guard) are documented on the packages themselves and
in the shipped usage skill `skills/diene-go-auth-engine-usage/SKILL.md`. The
authorization doctrine this library implements is the shared standard
[Authorization](docs/standards/authorization/index.md).

<!-- ### go-base-commands -->
<!-- #### source: go-base -->

## Go commands

- `pls build` — build every package in the module.
- `pls typecheck` — compile every source package without running tests.
- `pls test` / `pls test:coverage` — run unit, integration, and active meta tiers.
- `pls deadcode` — run strict whole-repository and production passes plus the LLM-lax report.
- `pls up` / `pls down` — start or stop local infrastructure (this library binds none).
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
