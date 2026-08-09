# Diene workspace agent guide

<!-- ### workspace -->
<!-- #### source: workspace -->

## Agent skills

`.claude/skills/vendor/` is tool-owned and is never hand-edited. Nothing in this
tree writes it: the tool that does is consumed per-template from the Nix registry,
and this tree declares no packages for it to vendor.

## CI/CD workflows

See [docs/standards/ci-cd/index.md](docs/standards/ci-cd/index.md).

## Conventional commits

See [docs/standards/conventional-commits/index.md](docs/standards/conventional-commits/index.md).

## Data validation

See [docs/standards/validation/index.md](docs/standards/validation/index.md).

## Date and time

See [docs/standards/datetime/index.md](docs/standards/datetime/index.md).

## Docker build and publishing

See [docs/standards/docker/index.md](docs/standards/docker/index.md).

## Domain-driven design

See [docs/standards/domain-driven-design/index.md](docs/standards/domain-driven-design/index.md).

## Functional practices

See [docs/standards/functional-practices/index.md](docs/standards/functional-practices/index.md).

## Helm charts and publishing

See [docs/standards/helm/index.md](docs/standards/helm/index.md).

## Infisical and secrets

See [docs/standards/infisical/index.md](docs/standards/infisical/index.md).

## Linting and pre-commit

See [docs/standards/linting/index.md](docs/standards/linting/index.md).

<!-- ### nix-root -->
<!-- #### source: main -->

## Nix flakes and development shells

Use the repository's Nix shell for every command. Read
[docs/standards/nix/index.md](docs/standards/nix/index.md) before changing the
flake or `nix/` modules.

## Release automation

See [docs/standards/semantic-release/index.md](docs/standards/semantic-release/index.md).

## Repository standards

Follow the linked standard before changing its surface. Domain-specific
architecture and behavior belongs under [docs/domain/](docs/domain/README.md),
not under `docs/standards/`.

## Service-tree identity

See [docs/standards/service-tree/index.md](docs/standards/service-tree/index.md).

## Shell scripts

See [docs/standards/shell-scripts/index.md](docs/standards/shell-scripts/index.md).

## Software design philosophy

See [docs/standards/software-design-philosophy/index.md](docs/standards/software-design-philosophy/index.md).

## SOLID principles

See [docs/standards/solid-principles/index.md](docs/standards/solid-principles/index.md).

## Stateless OOP and dependency injection

See [docs/standards/stateless-oop-di/index.md](docs/standards/stateless-oop-di/index.md).

## Taskfile conventions

See [docs/standards/taskfile/index.md](docs/standards/taskfile/index.md).

## Testing

See [docs/standards/testing/index.md](docs/standards/testing/index.md).

## Three-layer architecture

See [docs/standards/three-layer-architecture/index.md](docs/standards/three-layer-architecture/index.md).

## Utility libraries

See [docs/standards/utilities/index.md](docs/standards/utilities/index.md).

<!-- ### shared -->
<!-- #### source: shared -->

## Authorization

See [docs/standards/authorization/index.md](docs/standards/authorization/index.md).
The standard left the parent template with the .NET layer that is its only user,
so this node owns it.

<!-- ### dotnet-base -->
<!-- #### source: dotnet-base -->

## .NET base template

Read [the .NET baseline](docs/developer/dotnet-baseline.md) and use `task` for
setup, build, run, test, coverage, dead-code review, Docker, and Helm tasks.

Language variants:

- [C# date and time](docs/standards/datetime/languages/csharp.md)
- [C# domain-driven design](docs/standards/domain-driven-design/languages/csharp.md)
- [C# functional practices](docs/standards/functional-practices/languages/csharp.md)
- [C# SOLID principles](docs/standards/solid-principles/languages/csharp.md)
- [C# stateless OOP and DI](docs/standards/stateless-oop-di/languages/csharp.md)
- [C# testing](docs/standards/testing/languages/csharp.md)
- [C# utilities](docs/standards/utilities/languages/csharp.md)
- [C# validation](docs/standards/validation/languages/csharp.md)

Keep `dotnet-base.slnx`, `.config/dotnet-base.test.yaml`, and
`AtomiCloud.DotnetBase.*` root namespaces base-named. Observability is absent on
this branch.
