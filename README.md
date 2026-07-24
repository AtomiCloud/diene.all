# Diene workspace baseline

<!-- ### nix-root -->
<!-- #### source: main -->

Diene's reproducible development environment is managed by Nix. Run `direnv allow` once, then use `pls` tasks from the loaded shell.

<!-- ### workspace -->
<!-- #### source: workspace -->

This branch is the workspace baseline inherited by every downstream sample: split CI/CD, Helm, secrets, release configuration, validators, standards, and vendored agent-skill synchronization.

## Commands

- `pls setup` — synchronize installed diene package skills.
- `pls lint` — run every pre-commit gate.
- `pls helm:lint` / `pls helm:template` — validate or render the root chart.
- `pls secret:scan` — scan tracked content for secrets.
- `pls skills:sync` — rebuild `.claude/skills/vendor/` from installed packages.

## Standards

- [CI/CD workflows](docs/standards/ci-cd/index.md)
- [conventional commits](docs/standards/conventional-commits/index.md)
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

<!-- ### sulfur -->
<!-- #### source: sulfur -->

## Sulfur chart (cert-manager engine)

This branch is the sulfur cert-manager engine chart — a pure-passthrough wrapper
around `jetstack/cert-manager`, with the engine/issuer split (issuers live in
zinc), sequential-minor upgrades, Gateway API support, and an ordinary testing
pyramid.

- `pls build` — build the pinned cert-manager chart dependency.
- `pls test:unit` — run the unit pyramid: schema, lint, render, labels, Reloader,
  the Q-G20 rendered-manifest stage, the Q-G22 sequential-minor gate, and the
  contract negative fixtures.
- `pls test:int` — install checksum-pinned Gateway API CRDs plus sulfur on
  ephemeral k3d, then round-trip a self-signed Certificate to Ready (reserved
  for the orchestrated proof window).
- `pls example:lapras:template` — render the independent landscape + cluster stack.
- [Sulfur baseline](docs/developer/sulfur-baseline.md)
