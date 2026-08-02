# Diene workspace baseline

Diene's reproducible development environment is managed by Nix. Run `direnv allow` once, then use `pls` tasks from the loaded shell.

This branch is the workspace baseline inherited by every downstream sample: split CI/CD, Helm, secrets, release configuration, validators, standards, and vendored agent-skill synchronization.

## Commands

Run `pls --list` for every available task and its description. The task set is
declared in [`Taskfile.yaml`](Taskfile.yaml), whose `includes:` block maps each
namespace to a file under [`tasks/`](tasks); a task shown as `<namespace>:<task>`
is that key in the included file. Helm charts live under [`infra/`](infra) and
may be plural, so their tasks are keyed per
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

## Helm wrapper sample

This branch adds the production-grade wrapper chart, stacked values, generated schema, rendered-manifest validation, k3d proof, and dual publish modes.

- `pls build` — vendor external config and build pinned chart dependencies.
- `pls test:unit` — run schema, lint, render, contracts, VAP, and publish dry-runs.
- `pls test:int` — install on ephemeral k3d and round-trip the chart through a local OCI registry.
- `pls example:lapras:template` — render the independent landscape + cluster stack.
- [Helm wrapper baseline](docs/developer/helm-wrapper-baseline.md)
