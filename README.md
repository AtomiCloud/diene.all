# Diene .NET library template

<!-- ### nix-root -->
<!-- #### source: main -->

Diene's reproducible development environment is managed by Nix. Run `direnv allow` once, then use `pls` tasks from the loaded shell.

<!-- ### workspace -->
<!-- #### source: workspace -->

This branch is the workspace baseline inherited by every downstream sample: split CI/CD, secrets, release configuration, validators, standards, and vendored agent-skill synchronization.

## Commands

- `pls setup` — synchronize installed diene package skills.
- `pls lint` — run every pre-commit gate.
- `pls secret:scan` — scan tracked content for secrets.
- `pls skills:sync` — rebuild `.claude/skills/vendor/` from installed packages.

## Standards

- [CI/CD workflows](docs/standards/ci-cd/index.md)
- [conventional commits](docs/standards/conventional-commits/index.md)
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

<!-- ### dotnet-base -->
<!-- #### source: dotnet-base -->

## .NET 10 foundation

[![CI](https://github.com/AtomiCloud/diene.dotnet-lib/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.dotnet-lib/actions/workflows/ci.yaml)
[![Unit coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-lib/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.dotnet-lib)
[![Integration coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-lib/graph/badge.svg?flag=int)](https://codecov.io/gh/AtomiCloud/diene.dotnet-lib)
[![Commit activity](https://img.shields.io/github/commit-activity/m/AtomiCloud/diene.dotnet-lib)](https://github.com/AtomiCloud/diene.dotnet-lib/commits/main)

This branch adds the .NET 10 toolchain, the `App`/`Lib`/`UnitTest`/`IntTest`
sample, merged multi-project coverage, strict and LLM dead-code modes. See [the .NET baseline](docs/developer/dotnet-baseline.md).

Common commands:

- `pls build`, `pls dev`, `pls run`, and `pls preview`
- `pls test`, `pls test:unit`, `pls test:int`, and the coverage variants
- `pls deadcode` for the non-blocking review; CI owns strict dn-inspect

The config domain language is documented in [docs/domain/config.md](docs/domain/config.md).
Production observability is intentionally absent until the observability add-back.

<!-- ### dotnet-lib -->
<!-- #### source: dotnet-lib -->

## Publishable library packages

[![NuGet version](https://img.shields.io/nuget/v/AtomiCloud.Diene.Config)](https://www.nuget.org/packages/AtomiCloud.Diene.Config)
[![NuGet downloads](https://img.shields.io/nuget/dt/AtomiCloud.Diene.Config)](https://www.nuget.org/packages/AtomiCloud.Diene.Config)
[![Meta coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-config/graph/badge.svg?flag=meta)](https://codecov.io/gh/AtomiCloud/diene.dotnet-config)

This repository publishes `AtomiCloud.Diene.Config` and the companion
`AtomiCloud.Diene.Config.TestHelper` package at one committed version. It is
the sole config merger and validator for the Diene .NET family: it loads YAML
layers, applies the prefixed environment layer last, and validates the
service-composed root on the final merged layer only.

```bash
dotnet add package AtomiCloud.Diene.Config
dotnet add package AtomiCloud.Diene.Config.TestHelper
```

```csharp
using AtomiCloud.Diene.Config;

builder.Configuration.AddAtomiConfig(new AtomiConfigSource
{
    Landscape = landscape,   // blank reads the LANDSCAPE variable
    EnvPrefix = "ATOMI_",    // required: the library bakes no default
});

builder.Services.AddAtomiServiceTree();
builder.Services.RegisterOption<ErrorPortalOption, ErrorPortalOptionValidator>("ErrorPortal");
```

Keys match across every C0 spelling, so a snake_cased YAML key, a
`SCREAMING_SNAKE` environment variable, and a Pascal option property are one
key. Lists use indexed environment keys (`FOO__0`, `FOO__1`) — never
JSON-in-env and never comma encoding.

Run `nix develop .#ci -c ./scripts/ci/pkg-validate.sh` to pack both packages,
validate metadata and symbols, and restore them into a scratch consumer. See
[the library baseline](docs/developer/dotnet-lib-baseline.md) for release and
promotion guidance.
