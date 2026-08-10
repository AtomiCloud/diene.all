# Diene workspace baseline

Diene's reproducible development environment is managed by Nix. Run `direnv allow` once, then use `task` tasks from the loaded shell.

This branch is the workspace baseline without Docker, inherited by every downstream sample: split CI/CD, Helm, secrets, release configuration, validators, and standards.

## Commands

Run `task --list` for every available task and its description. The task set is
declared in [`Taskfile.yaml`](Taskfile.yaml), whose `includes:` block maps each
namespace to a file under [`tasks/`](tasks); a task shown as `<namespace>:<task>`
is that key in the included file. Build artifacts — Helm charts — live under
[`infra/`](infra) and may be plural, so their tasks are keyed per artifact. See [the Taskfile standard](docs/standards/taskfile/index.md) for the
conventions.

## Standards

The conventions this repository follows live under
[`docs/standards/`](docs/standards). Read the standard for the surface you are
changing before you change it. [`CLAUDE.md`](CLAUDE.md) links the ones an agent
reaches for most often; it is a convenience, not a required index, and nothing
checks that it names every surface.

Domain-specific architecture and behavior belongs under
[`docs/domain/`](docs/domain/README.md), not under `docs/standards/`.

<!-- ### cobalt -->
<!-- #### source: cobalt -->

## Cobalt chart

This branch is the External Secrets Operator plus the Infisical source-of-secrets `ClusterSecretStore` gateway: a materialized chart product with stacked values, generated schema, rendered-manifest validation, dual publish modes, and a reserved k3d integration tier.

- `task build` — build the pinned upstream chart dependency.
- `task test:unit` — run schema, lint, render, VAP, store-contract, and publish dry-runs.
- `task test:int` — install on ephemeral k3d and round-trip the chart through a local OCI registry (reserved proof).
- `task example:lapras:template` — render the independent landscape + cluster stack.
- [Cobalt baseline](docs/developer/cobalt-baseline.md)
