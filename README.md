# Diene Go language base

[![CI](https://github.com/AtomiCloud/diene.go-base/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.go-base/actions/workflows/ci.yaml)
[![Unit coverage](https://codecov.io/gh/AtomiCloud/diene.go-base/branch/main/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.go-base)
[![Integration coverage](https://codecov.io/gh/AtomiCloud/diene.go-base/branch/main/graph/badge.svg?flag=int)](https://codecov.io/gh/AtomiCloud/diene.go-base)
[![Commit activity](https://img.shields.io/github/commit-activity/m/AtomiCloud/diene.go-base)](https://github.com/AtomiCloud/diene.go-base/commits/main)

Diene's reproducible development environment is managed by Nix. Run `direnv allow` once, then use `task` tasks from the loaded shell.

This repository inherits the all-features workspace baseline: split CI/CD, Docker, Helm, secrets, release configuration, validators, standards, and vendored agent-skill synchronization.

## Commands

Run `task --list` for every available task and its description. The task set is
declared in [`Taskfile.yaml`](Taskfile.yaml), whose `includes:` block maps each
namespace to a file under [`tasks/`](tasks); a task shown as `<namespace>:<task>`
is that key in the included file. Build artifacts — Dockerfiles and Helm charts —
live under [`infra/`](infra) and may be plural, so their tasks are keyed per
artifact. See [the Taskfile standard](docs/standards/taskfile/index.md) for the
conventions.

## Go commands

- `pls build` — create `dist/go-base`.
- `pls typecheck` — compile every source package without running tests.
- `pls test` — run the unit, integration, and system integration tiers.
- `pls test:coverage` — enforce the scoped unit and integration coverage ledgers.
- `pls deadcode` — run strict whole-repository and production passes plus the LLM-lax report.
- `pls run -- slug "Hello World"` — execute from source.
- `pls preview -- slug "Hello World"` — execute the compiled artifact.
- `pls up` / `pls down` — start or stop local Redis.

See the [Go baseline](docs/developer/go-baseline.md) for the language contract and
template-maintenance boundary.

## Standards

The conventions this repository follows live under
[`docs/standards/`](docs/standards). Read the standard for the surface you are
changing before you change it. [`CLAUDE.md`](CLAUDE.md) links the ones an agent
reaches for most often; it is a convenience, not a required index, and nothing
checks that it names every surface.

Domain-specific architecture and behavior belongs under
[`docs/domain/`](docs/domain/README.md), not under `docs/standards/`.

## Go language variants

- [Date and time](docs/standards/datetime/languages/go.md)
- [Domain-driven design](docs/standards/domain-driven-design/languages/go.md)
- [Functional practices](docs/standards/functional-practices/languages/go.md)
- [SOLID principles](docs/standards/solid-principles/languages/go.md)
- [Stateless OOP and dependency injection](docs/standards/stateless-oop-di/languages/go.md)
- [Testing](docs/standards/testing/languages/go.md)
- [Utilities](docs/standards/utilities/languages/go.md)
- [Validation](docs/standards/validation/languages/go.md)
