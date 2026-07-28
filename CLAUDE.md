# Diene workspace agent guide

<!-- ### nix-root -->
<!-- #### source: main -->

Use the repository's Nix shell for every command. Read [the Nix standard](docs/standards/nix/index.md) before changing the flake or `nix/` modules.

<!-- ### workspace -->
<!-- #### source: workspace -->

Follow the linked standard before changing its surface. Keep many-owner files in keyed, source-attributed blocks and never hand-edit `.claude/skills/vendor/`.

## CI/CD workflows

See [docs/standards/ci-cd/index.md](docs/standards/ci-cd/index.md).

## Conventional commits

See [docs/standards/conventional-commits/index.md](docs/standards/conventional-commits/index.md).

## Infisical and secrets

See [docs/standards/infisical/index.md](docs/standards/infisical/index.md).

## Linting and pre-commit

See [docs/standards/linting/index.md](docs/standards/linting/index.md).

## Nix flakes and development shells

See [docs/standards/nix/index.md](docs/standards/nix/index.md).

## Release automation

See [docs/standards/semantic-release/index.md](docs/standards/semantic-release/index.md).

## Service-tree identity

See [docs/standards/service-tree/index.md](docs/standards/service-tree/index.md).

## Shell scripts

See [docs/standards/shell-scripts/index.md](docs/standards/shell-scripts/index.md).

## Taskfile conventions

See [docs/standards/taskfile/index.md](docs/standards/taskfile/index.md).

<!-- ### shared -->
<!-- #### source: shared -->

## Shared engineering standards

- [Authorization](docs/standards/authorization/index.md)
- [Contributor documentation](docs/standards/contributor-docs/index.md)
  ([checklist](docs/standards/contributor-docs/checklist.md),
  [classification](docs/standards/contributor-docs/classification.md),
  [frontmatter](docs/standards/contributor-docs/frontmatter.md), and
  [structure](docs/standards/contributor-docs/structure.md))
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

Domain-specific architecture and behavior belongs under
[docs/domain/](docs/domain/README.md). The `docs/standards/contracts/` slot is
reserved for the separately owned C0 contracts standard.

<!-- ### dotnet-base -->
<!-- #### source: dotnet-base -->

## .NET base template

Read [the .NET baseline](docs/developer/dotnet-baseline.md) and use `pls` for
setup, build, run, test, coverage, and dead-code review.

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

<!-- ### dotnet-lib -->
<!-- #### source: dotnet-lib -->

## .NET library template

Read [the .NET library baseline](docs/developer/dotnet-lib-baseline.md) before
changing package identity, release/versioning, package validation, TestHelper,
meta coverage, or shipped skills.
