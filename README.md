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

<!-- ### sulfur -->
<!-- #### source: sulfur -->

## Sulfur chart

This branch materializes the pure-passthrough cert-manager engine wrapper chart, its stacked values, generated schema, Gateway API / sequential-minor / issuer-boundary gates, rendered-manifest validation, and k3d integration proof.

- `task build` — vendor and build the pinned cert-manager dependency.
- `task test:unit` — run schema, lint, render, labels, Gateway API, CRD, issuer-boundary, sequential-minor, VAP, and publish dry-runs.
- `task test:int` — install the engine on ephemeral k3d and round-trip a self-signed Certificate to Ready=True.
- `task example:lapras:template` — render the independent landscape + cluster stack.
- [Sulfur baseline](docs/developer/sulfur-baseline.md)
