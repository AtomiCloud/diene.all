# Diene .NET API sample

Diene's reproducible development environment is managed by Nix. Run `direnv allow` once, then use `task` tasks from the loaded shell.

This branch is the all-features workspace baseline inherited by every downstream sample: split CI/CD, Docker, Helm, secrets, release configuration, validators, and standards.

## Commands

Run `task --list` for every available task and its description. The task set is
declared in [`Taskfile.yaml`](Taskfile.yaml), whose `includes:` block maps each
namespace to a file under [`tasks/`](tasks); a task shown as `<namespace>:<task>`
is that key in the included file. Build artifacts — Dockerfiles and Helm charts —
live under [`infra/`](infra) and may be plural, so their tasks are keyed per
artifact. See [the Taskfile standard](docs/standards/taskfile/index.md) for the
conventions.

## Standards

The conventions this repository follows live under
[`docs/standards/`](docs/standards). Read the standard for the surface you are
changing before you change it. [`CLAUDE.md`](CLAUDE.md) links the ones an agent
reaches for most often; it is a convenience, not a required index, and nothing
checks that it names every surface.

Domain-specific architecture and behavior belongs under
[`docs/domain/`](docs/domain/README.md), not under `docs/standards/`.

<!-- ### shared -->
<!-- #### source: shared -->

## Shared standards

- [Authorization](docs/standards/authorization/index.md)
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

<!-- ### dotnet-base -->
<!-- #### source: dotnet-base -->

## .NET 10 foundation

This branch adds the .NET 10 toolchain, the `App`/`Lib`/`UnitTest`/`IntTest`
sample, merged multi-project coverage, strict and LLM dead-code modes, and the
complete Docker and Helm axes. See [the .NET baseline](docs/developer/dotnet-baseline.md).

Common commands:

- `task build`, `task dev`, `task run`, and `task preview`
- `task test`, `task test:unit`, `task test:int`, and the coverage variants
- `task deadcode` for the non-blocking review; CI owns strict dn-inspect
- `task docker:build:main` and `task helm:root_chart:lint` / `task helm:root_chart:template`

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
