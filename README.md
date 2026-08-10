# Diene Go consumer

[![CI](https://github.com/AtomiCloud/diene.go-consumer/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.go-consumer/actions/workflows/ci.yaml)
[![Unit coverage](https://codecov.io/gh/AtomiCloud/diene.go-consumer/branch/main/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.go-consumer)
[![Integration coverage](https://codecov.io/gh/AtomiCloud/diene.go-consumer/branch/main/graph/badge.svg?flag=int)](https://codecov.io/gh/AtomiCloud/diene.go-consumer)
[![Commit activity](https://img.shields.io/github/commit-activity/m/AtomiCloud/diene.go-consumer)](https://github.com/AtomiCloud/diene.go-consumer/commits/main)

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

- `task build` — create `dist/go-consumer`.
- `task typecheck` — compile every source package without running tests.
- `task test` — run the unit, integration, and system integration tiers.
- `task test:coverage` — enforce the scoped unit and integration coverage ledgers.
- `task deadcode` — run strict whole-repository and production passes plus the LLM-lax report.

See the [Go baseline](docs/developer/go-baseline.md) for the language contract and
template-maintenance boundary.

<!-- ### go-consumer-commands -->
<!-- #### source: go-consumer -->

## Go consumer commands

- `task dev` — run the worker against the local dependency stack.
- `task run -- worker` / `task run -- db-init` / `task run -- health` — execute from source.
- `task preview -- worker` — execute the compiled artifact.
- `task up` / `task down` — start or stop Postgres, Redis, MinIO, and the telemetry backends.
- `task test:sit` — run the journeys through the compiled binary.
- `task test:sit:parity` — run the same journeys through both drivers and compare them.
- `task schema:gen` — regenerate `schemas/go-consumer.schema.json`.
- `task problems:export` — export the Problem catalog for the primordial chart.

See the [Go consumer delta](docs/developer/go-consumer.md) for the worker/db-init/health
composition, the configuration contract, and the two-chart model.

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
