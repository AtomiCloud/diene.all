# Diene .NET Problems

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

[![CI](https://github.com/AtomiCloud/diene.dotnet-problems/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.dotnet-problems/actions/workflows/ci.yaml)
[![Unit coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-problems/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.dotnet-problems)
[![Integration coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-problems/graph/badge.svg?flag=int)](https://codecov.io/gh/AtomiCloud/diene.dotnet-problems)
[![Commit activity](https://img.shields.io/github/commit-activity/m/AtomiCloud/diene.dotnet-problems)](https://github.com/AtomiCloud/diene.dotnet-problems/commits/main)

This branch adds the .NET 10 toolchain, the `App`/`Lib`/`UnitTest`/`IntTest`
sample, merged multi-project coverage, strict and LLM dead-code modes. See [the .NET baseline](docs/developer/dotnet-baseline.md).

Common commands:

- `task build`, `task dev`, `task run`, and `task preview`
- `task test`, `task test:unit`, `task test:int`, and the coverage variants
- `task deadcode` for the non-blocking review; CI owns strict dn-inspect

The typed-problem contract is documented in [docs/domain/problems.md](docs/domain/problems.md).
Production observability is intentionally absent until the observability add-back.

<!-- ### dotnet-lib -->
<!-- #### source: dotnet-lib -->

## Typed problem packages

[![NuGet version](https://img.shields.io/nuget/v/AtomiCloud.Diene.Problems)](https://www.nuget.org/packages/AtomiCloud.Diene.Problems)
[![NuGet downloads](https://img.shields.io/nuget/dt/AtomiCloud.Diene.Problems)](https://www.nuget.org/packages/AtomiCloud.Diene.Problems)
[![Meta coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-problems/graph/badge.svg?flag=meta)](https://codecov.io/gh/AtomiCloud/diene.dotnet-problems)

`AtomiCloud.Diene.Problems` provides typed domain problems, a consumer-owned
catalog, the canonical type-URI builder, RFC 9457 rendering, schema export, and
Problem custom-resource emission. `AtomiCloud.Diene.Problems.TestHelper`
provides FluentAssertions for domain, result, envelope, and HTTP boundaries.

```bash
dotnet add package AtomiCloud.Diene.Problems
dotnet add package AtomiCloud.Diene.Problems.TestHelper
```

### Register and render problems

Problem types do not enter the runtime implicitly. Register every baseline and
consumer-owned problem at composition time, then enable ASP.NET Core's exception
handler middleware:

```csharp
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.Catalog;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddAtomiProblems(
    new ProblemIdentity("raichu", "dotnet", "notes", "api"),
    new ErrorPortalOption
    {
        Scheme = "https",
        Host = "docs.raichu.cluster.atomi.cloud",
    },
    catalog => catalog.AddBaseline());

var app = builder.Build();
app.UseExceptionHandler();
```

Throw a registered problem only at a framework boundary. Within domain code,
prefer the Result-returning guards and adapters:

```csharp
var guarded = ProblemGuard.NotFound(note, noteId);
var failed = new ValidationError("The note is invalid.", errors).ToErr<Note>();
throw new EntityNotFound(
    $"Note '{noteId}' was not found.",
    typeof(Note),
    noteId).ToException();
```

### Type URIs and catalog export

Resolve `IProblemTypeUriBuilder` whenever a type URI is needed. Never recreate
the URI template in a controller or consumer. Resolve `ProblemResourceEmitter`
from the same service provider to emit the registered single-version catalog as
canonical JSON, which is also valid YAML 1.2:

```csharp
var emitter = app.Services.GetRequiredService<ProblemResourceEmitter>();
var resource = emitter.Emit(new ProblemResourceIdentity("dotnet", "notes", "raichu", "v1"));
var manifest = emitter.Serialize(resource);
```

### Assert the wire contract

```csharp
using AtomiCloud.Diene.Problems.TestHelper;
using FluentAssertions;

var envelope = (await response.Should().BeRfc9457()).Which;
envelope.Should().HaveStatus(404);
envelope.Should().HaveType(expectedTypeUri);
envelope.Should().HaveData(expectedProblem);
envelope.Should().BeRecoverable(false);
```

Run `nix develop .#ci -c ./scripts/ci/pkg-validate.sh` to pack both packages,
validate metadata and symbols, and restore them into a scratch consumer. See
[the library baseline](docs/developer/dotnet-lib-baseline.md) for release and
promotion guidance.
