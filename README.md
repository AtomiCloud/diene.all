# Diene .NET base template

Diene's reproducible development environment is managed by Nix. Run `direnv allow` once, then use `pls` tasks from the loaded shell.

This branch is the all-features workspace baseline inherited by every downstream sample: split CI/CD, Docker, Helm, secrets, release configuration, validators, standards, and vendored agent-skill synchronization.

## Commands

Run `pls --list` for every available task and its description. The task set is
declared in [`Taskfile.yaml`](Taskfile.yaml), whose `includes:` block maps each
namespace to a file under [`tasks/`](tasks); a task shown as `<namespace>:<task>`
is that key in the included file. Build artifacts — Dockerfiles and Helm charts —
live under [`infra/`](infra) and may be plural, so their tasks are keyed per
artifact. See [the Taskfile standard](docs/standards/taskfile/index.md) for the
conventions.

## Standards

[`CLAUDE.md`](CLAUDE.md) is the index of repository conventions: one section per
surface, each pointing at its standard under
[`docs/standards/`](docs/standards). Read the section for the surface you are
changing before you change it. The index covers both the tooling surfaces of
this baseline and the language-agnostic engineering standards it carries.

Domain-specific architecture and behavior belongs under
[`docs/domain/`](docs/domain/README.md), not under `docs/standards/`. The
[`docs/standards/contracts/`](docs/standards/contracts/README.md) location is
reserved for the separately owned C0 contracts standard.

## .NET 10 foundation

[![CI](https://github.com/AtomiCloud/diene.dotnet-base/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.dotnet-base/actions/workflows/ci.yaml)
[![Unit coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-base/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.dotnet-base)
[![Integration coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-base/graph/badge.svg?flag=int)](https://codecov.io/gh/AtomiCloud/diene.dotnet-base)
[![Commit activity](https://img.shields.io/github/commit-activity/m/AtomiCloud/diene.dotnet-base)](https://github.com/AtomiCloud/diene.dotnet-base/commits/main)

This branch adds the .NET 10 toolchain, the `App`/`Lib`/`UnitTest`/`IntTest`
sample, merged multi-project coverage, strict and LLM dead-code modes, and the
complete Docker and Helm axes. See [the .NET baseline](docs/developer/dotnet-baseline.md).

Common commands:

- `pls build`, `pls dev`, `pls run`, and `pls preview`
- `pls test`, `pls test:unit`, `pls test:int`, and the coverage variants
- `pls deadcode` for the non-blocking review; CI owns strict dn-inspect
- `pls docker:build:main` and `pls helm:root_chart:lint` / `pls helm:root_chart:template`

The illustrative Note domain is documented in [docs/domain/note.md](docs/domain/note.md).
Production observability is intentionally absent until the observability add-back.
