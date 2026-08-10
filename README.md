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

<!-- ### platinum -->
<!-- #### source: platinum -->

## Platinum Gateway API chart

This branch materializes the platform Gateway API ingress chart (element platinum, wrapping kgateway): shared GatewayClass/Gateway, the `/healthz` route, per-cloud fixed-IP LoadBalancer exposure, registered-fleet wildcard certificates, and the ENTEI dev-host shared-Gateway overlay.

- `task build` — build pinned kgateway + kgateway-crds dependencies.
- `task latest` — resolve the latest upstream kgateway chart, CRD, and image tags.
- `task test:unit` — run schema, lint, render, gateway, VAP (with NodePort sabotage), and publish dry-runs.
- `task test:int` — install on ephemeral k3d with the live kgateway control plane and prove the Gateway reaches `Programmed=True`.
- `task example:lapras:template` — render the independent landscape + cluster stack.
- [Platinum baseline](docs/developer/platinum-baseline.md)
