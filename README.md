# AtomiCloud.Diene.Result

Diene's reproducible development environment is managed by Nix. Run `direnv allow` once, then use `task` tasks from the loaded shell.

This branch is the all-features workspace baseline inherited by every downstream sample: split CI/CD, secrets, release configuration, validators, and standards.

## Commands

Run `task --list` for every available task and its description. The task set is
declared in [`Taskfile.yaml`](Taskfile.yaml), whose `includes:` block maps each
namespace to a file under [`tasks/`](tasks); a task shown as `<namespace>:<task>`
is that key in the included file. See [the Taskfile standard](docs/standards/taskfile/index.md) for the
conventions.

## Standards

The conventions this repository follows live under
[`docs/standards/`](docs/standards). Read the standard for the surface you are
changing before you change it. [`CLAUDE.md`](CLAUDE.md) links the ones an agent
reaches for most often; it is a convenience, not a required index, and nothing
checks that it names every surface.

Domain-specific architecture and behavior belongs under
[`docs/domain/`](docs/domain/README.md), not under `docs/standards/`.

<!-- ### shared -->
<!-- #### source: shared -->

## Shared standards

- [Authorization](docs/standards/authorization/index.md)
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

<!-- ### dotnet-base -->
<!-- #### source: dotnet-base -->

## .NET 10 foundation

[![CI](https://github.com/AtomiCloud/diene.dotnet-result/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.dotnet-result/actions/workflows/ci.yaml)
[![Unit coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-result/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.dotnet-result)
[![Integration coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-result/graph/badge.svg?flag=int)](https://codecov.io/gh/AtomiCloud/diene.dotnet-result)
[![Commit activity](https://img.shields.io/github/commit-activity/m/AtomiCloud/diene.dotnet-result)](https://github.com/AtomiCloud/diene.dotnet-result/commits/main)

This branch adds the .NET 10 toolchain, the `App`/`Lib`/`UnitTest`/`IntTest`
sample, merged multi-project coverage, strict and LLM dead-code modes. See [the .NET baseline](docs/developer/dotnet-baseline.md).

Common commands:

- `task build`, `task dev`, `task run`, and `task preview`
- `task test`, `task test:unit`, `task test:int`, and the coverage variants
- `task deadcode` for the non-blocking review; CI owns strict dn-inspect

The Result/Option contract is documented in [docs/domain/result.md](docs/domain/result.md).

<!-- ### dotnet-lib -->
<!-- #### source: dotnet-lib -->

## Publishable library packages

[![NuGet version](https://img.shields.io/nuget/v/AtomiCloud.Diene.Result)](https://www.nuget.org/packages/AtomiCloud.Diene.Result)
[![NuGet downloads](https://img.shields.io/nuget/dt/AtomiCloud.Diene.Result)](https://www.nuget.org/packages/AtomiCloud.Diene.Result)
[![Meta coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-result/graph/badge.svg?flag=meta)](https://codecov.io/gh/AtomiCloud/diene.dotnet-result)

This repository publishes `AtomiCloud.Diene.Result` and the companion
`AtomiCloud.Diene.Result.TestHelper` package at one committed version. The
library provides guarded rich structs for `Result<T, E>` and `Option<T>`,
dotnet-idiomatic railway composition, explicit exception capture, async
composition, and versioned C0 JSON tuple codecs. It has no runtime dependency
and no dependency on a Problems package.

```bash
dotnet add package AtomiCloud.Diene.Result
dotnet add package AtomiCloud.Diene.Result.TestHelper
```

```csharp
using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.Results.TestHelper;

Result<int, string> parsed = Result.Ok<int, string>(21);
var answer = parsed.Map(value => value * 2);
answer.Should().BeOk(42);
```

The package ID is singular but the namespace is plural
`AtomiCloud.Diene.Results`; this avoids the namespace/type collision between a
namespace tail and the `Result` type. Use `Result.Ok`/`Result.Err` when the
success and error types are identical. Serialize only `ResultSerial` and
`OptionSerial`, never the in-memory structs.

Run `nix develop .#ci -c ./scripts/ci/pkg-validate.sh` to pack both packages,
validate metadata and symbols, and restore them into a scratch consumer. See
[the library baseline](docs/developer/dotnet-lib-baseline.md) for release and
promotion guidance.
