# Diene .NET API sample

<!-- ### nix-root -->
<!-- #### source: main -->

Diene's reproducible development environment is managed by Nix. Run `direnv allow` once, then use `pls` tasks from the loaded shell.

<!-- ### workspace -->
<!-- #### source: workspace -->

This branch is the all-features workspace baseline inherited by every downstream sample: split CI/CD, Docker, Helm, secrets, release configuration, validators, standards, and vendored agent-skill synchronization.

## Commands

- `pls setup` — synchronize installed diene package skills.
- `pls lint` — run every pre-commit gate.
- `pls docker:build` — build the local service image.
- `pls helm:lint` / `pls helm:template` — validate or render the root chart.
- `pls secret:scan` — scan tracked content for secrets.
- `pls skills:sync` — rebuild `.claude/skills/vendor/` from installed packages.

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

<!-- ### dotnet-base -->
<!-- #### source: dotnet-base -->

## .NET 10 foundation

This branch adds the .NET 10 toolchain, the `App`/`Lib`/`UnitTest`/`IntTest`
sample, merged multi-project coverage, strict and LLM dead-code modes, and the
complete Docker and Helm axes. See [the .NET baseline](docs/developer/dotnet-baseline.md).

Common commands:

- `pls build`, `pls dev`, `pls run`, and `pls preview`
- `pls test`, `pls test:unit`, `pls test:int`, and the coverage variants
- `pls deadcode` for the non-blocking review; CI owns strict dn-inspect
- `pls docker:build` and `pls helm:lint` / `pls helm:template`

The illustrative Note domain is documented in [docs/domain/note.md](docs/domain/note.md).

<!-- ### dotnet-api -->
<!-- #### source: dotnet-api -->

## The service sample

[![CI](https://github.com/AtomiCloud/diene.dotnet-api/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.dotnet-api/actions/workflows/ci.yaml)
[![Unit coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-api/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.dotnet-api)
[![Integration coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-api/graph/badge.svg?flag=int)](https://codecov.io/gh/AtomiCloud/diene.dotnet-api)
[![Commit activity](https://img.shields.io/github/commit-activity/m/AtomiCloud/diene.dotnet-api)](https://github.com/AtomiCloud/diene.dotnet-api/commits/main)

This repository is a runnable, deployable ASP.NET Core service — not a template.
It is the living consumer of the `AtomiCloud.Diene.*` libraries, every one of which
it takes as a published nuget.org package.

The compiled artifact is two things: `server`, which serves HTTP and is the
default, and `db-init`, the one-shot path that checks dependency reachability,
creates the bucket, applies real EF Core migrations, and seeds preset data. The
chart runs `db-init` as a hook-scoped Job before the rollout, so a migration never
recreates the app.

`GET /` is the info endpoint and the target of both the liveness and the readiness
probe. It is dependency-blind on purpose: it reports that this process is serving
and nothing more.

All behaviour is configuration. `App/Config/settings.yaml` is the full base layer,
and every value is overridable per landscape and at CI as `ATOMI_<BLOCK>__<KEY>`;
lists use indexed keys such as `ATOMI_HTTP__CORS__ALLOWED_ORIGINS__0`.

Beyond the inherited task surface, this repository adds the Bruno SIT tier in
[`tests/sit/bruno/`](tests/sit/bruno/README.md), which runs headless against a
Garden-managed `castform` preview.

Read [the .NET API baseline](docs/developer/dotnet-api-baseline.md) for the run
modes, the task surface, and the knobs a downstream service turns.

Production observability is intentionally absent until the observability add-back.
