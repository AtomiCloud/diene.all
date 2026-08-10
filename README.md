# operator-template

The reusable kubebuilder/controller-runtime operator skeleton in family
conventions — a manager image plus manager chart, proven on a toy CRD pair.

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

- `task build` — create `dist/manager`.
- `task typecheck` — compile every source package without running tests.
- `task test` — run the unit and integration tiers.
- `task test:coverage` — enforce the scoped unit and integration coverage ledgers.
- `task deadcode` — run strict whole-repository and production passes plus the LLM-lax report.
- `task run -- --help` — run the manager from source.
- `task preview -- --help` — run the compiled manager artifact.
- `task operator:generate` — regenerate CRDs, RBAC, and deepcopy from the Go types.
- `task operator:e2e` — run the k3d end-to-end journey.

See the [Go baseline](docs/developer/go-baseline.md) for the language contract and
template-maintenance boundary, and the
[operator conventions](docs/domain/operator-conventions.md) for the operator surface.

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
