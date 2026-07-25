# AtomiCloud.Diene.Interfaces

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

[![CI](https://github.com/AtomiCloud/diene.dotnet-interfaces/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.dotnet-interfaces/actions/workflows/ci.yaml)
[![Unit coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-interfaces/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.dotnet-interfaces)
[![Integration coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-interfaces/graph/badge.svg?flag=int)](https://codecov.io/gh/AtomiCloud/diene.dotnet-interfaces)
[![Commit activity](https://img.shields.io/github/commit-activity/m/AtomiCloud/diene.dotnet-interfaces)](https://github.com/AtomiCloud/diene.dotnet-interfaces/commits/main)

This branch adds the .NET 10 toolchain, the `App`/`Lib`/`UnitTest`/`IntTest`
sample, merged multi-project coverage, strict and LLM dead-code modes. See [the .NET baseline](docs/developer/dotnet-baseline.md).

Common commands:

- `pls build`, `pls dev`, `pls run`, and `pls preview`
- `pls test`, `pls test:unit`, `pls test:int`, and the coverage variants
- `pls deadcode` for the non-blocking review; CI owns strict dn-inspect

The shared seams and their C0 wire contract are documented in
[docs/domain/interfaces.md](docs/domain/interfaces.md).
Production observability is intentionally absent until the observability add-back.

<!-- ### dotnet-lib -->
<!-- #### source: dotnet-lib -->

## Publishable library packages

[![NuGet version](https://img.shields.io/nuget/v/AtomiCloud.Diene.Interfaces)](https://www.nuget.org/packages/AtomiCloud.Diene.Interfaces)
[![NuGet downloads](https://img.shields.io/nuget/dt/AtomiCloud.Diene.Interfaces)](https://www.nuget.org/packages/AtomiCloud.Diene.Interfaces)
[![Meta coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-interfaces/graph/badge.svg?flag=meta)](https://codecov.io/gh/AtomiCloud/diene.dotnet-interfaces)

This repository publishes `AtomiCloud.Diene.Interfaces` and the companion
`AtomiCloud.Diene.Interfaces.TestHelper` package at one committed version. It is
the .NET member of the S33 cross-family common-interfaces library: it OWNS the
shared seams for `ISystem`, `IVfs`, `ITerminal`, `ILoggerSink`, and
`IMetricsCollector`, and every fallible method returns
`Result<T, SeamError>` — it never throws and never captures. The `otel` package
IMPLEMENTS the telemetry seams; it does not own them.

```bash
dotnet add package AtomiCloud.Diene.Interfaces
dotnet add package AtomiCloud.Diene.Interfaces.TestHelper
```

```csharp
using AtomiCloud.Diene.Interfaces;
using AtomiCloud.Diene.Interfaces.TestHelper;
using AtomiCloud.Diene.Results.TestHelper;

// Substitute the in-memory seam anywhere an IVfs is required.
var vfs = new InMemoryVfs();
(await vfs.WriteText("/etc/app.yaml", "key: value", new VfsWriteOptions(true))).Should().BeOk();
(await vfs.ReadText("/etc/app.yaml")).Should().BeOk("key: value");
(await vfs.ReadText("/absent")).Should().BeSeamErr(SeamKind.Vfs, "not_found");

// Prove YOUR implementation satisfies the same behavioural contract.
(await SeamContracts.Vfs(new MyVfs(), "/tmp/scratch")).Should().BeConformant();
```

The shipped `SeamContracts` suites are the contract-parity vehicle: run one suite
against your real adapter and against the in-memory mock, and a conformant pair is
substitutable. Values that cross the wire obey the C0 contract (R14) — RFC 3339
UTC instants, ISO 8601 durations, IANA timezone ids, and one stable lowercase wire
name per enumeration, shared with the bun, dart, and go members of this family.

Run `nix develop .#ci -c ./scripts/ci/pkg-validate.sh` to pack both packages,
validate metadata and symbols, and restore them into a scratch consumer. See
[the library baseline](docs/developer/dotnet-lib-baseline.md) for release and
promotion guidance.
