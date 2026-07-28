# Diene .NET API Engine

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

[![CI](https://github.com/AtomiCloud/diene.dotnet-api-engine/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.dotnet-api-engine/actions/workflows/ci.yaml)
[![Unit coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-api-engine/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.dotnet-api-engine)
[![Integration coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-api-engine/graph/badge.svg?flag=int)](https://codecov.io/gh/AtomiCloud/diene.dotnet-api-engine)
[![Commit activity](https://img.shields.io/github/commit-activity/m/AtomiCloud/diene.dotnet-api-engine)](https://github.com/AtomiCloud/diene.dotnet-api-engine/commits/main)

This branch adds the .NET 10 toolchain, the `App`/`Lib`/`UnitTest`/`IntTest`
sample, merged multi-project coverage, strict and LLM dead-code modes. See [the .NET baseline](docs/developer/dotnet-baseline.md).

Common commands:

- `pls build`, `pls dev`, `pls run`, and `pls preview`
- `pls test`, `pls test:unit`, `pls test:int`, and the coverage variants
- `pls deadcode` for the non-blocking review; CI owns strict dn-inspect

The client contract is documented in [docs/domain/api-engine.md](docs/domain/api-engine.md).
Production observability is intentionally absent until the observability add-back.

<!-- ### dotnet-lib -->
<!-- #### source: dotnet-lib -->

## API engine packages

[![NuGet version](https://img.shields.io/nuget/v/AtomiCloud.Diene.ApiEngine)](https://www.nuget.org/packages/AtomiCloud.Diene.ApiEngine)
[![NuGet downloads](https://img.shields.io/nuget/dt/AtomiCloud.Diene.ApiEngine)](https://www.nuget.org/packages/AtomiCloud.Diene.ApiEngine)
[![Meta coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-api-engine/graph/badge.svg?flag=meta)](https://codecov.io/gh/AtomiCloud/diene.dotnet-api-engine)

`AtomiCloud.Diene.ApiEngine` is the typed backend-client layer: an LPSM client
tree over generated SDKs, per-backend token attachment, a
retry-once-on-network-error transport profile, and full classification of every
response into `Result<T, Problem>`. It is a client only — the MVC controller base
and the exception-to-problem filter live in `AtomiCloud.Diene.ServerEngine`.
`AtomiCloud.Diene.ApiEngine.TestHelper` provides the fake upstreams, response
fixtures, and outcome assertions consumers would otherwise write per project.

```bash
dotnet add package AtomiCloud.Diene.ApiEngine
dotnet add package AtomiCloud.Diene.ApiEngine.TestHelper
```

### Register a backend

Each upstream is declared once, addressed by the service tree, with its base
address and timeout read from the engine-owned `HttpClient` configuration block:

```csharp
using AtomiCloud.Diene.ApiEngine.Client;
using AtomiCloud.Diene.ApiEngine.Config;
using AtomiCloud.Diene.ApiEngine.Module;

var address = ServiceAddress.Create("lithium", "notes", "note").Get();
var config = ApiEngineConfig.Create(options).Get();

builder.Services.AddAtomiClientTree(config, tree => tree
    .Register(address, http => new NotesClient(http)));
```

Each registration produces a named `HttpClient` carrying the engine's handler
pipeline plus a keyed typed client over it, so a call site may resolve through
`IClientTree` or inject `[FromKeyedServices("lithium.notes.note")]` directly. An
upstream with an `authResource` gets its own auth handler bound to that resource,
so a backend can only ever carry its own credential.

### Call through the wrapper

```csharp
var outcome = await caller.Call(address, ct => client.GetNoteAsync(id, ct));

return outcome.Match(
    note => Results.Ok(note),
    problem => Results.Problem(problem.Detail, statusCode: problem.Status));
```

No exception escapes. A successful call yields its value; an upstream problem
envelope is passed through verbatim; a JSON failure that is not a problem becomes
`UpstreamRejected` (502); anything unreadable — a non-JSON body, a bare status, a
dropped connection, a timeout — becomes `UpstreamTransportFailure` (504). Only
the last is recoverable, and the two are separate types precisely so a caller can
tell "the service said no" from "there was no answer".

### Test against a fake upstream

```csharp
var upstream = new FakeUpstream("notes");
upstream.RespondNetworkFailure();
upstream.RespondOk(UpstreamResponses.Payload(new { id = "n-1" }));

services.AddHttpClient("lithium.notes.note")
    .ConfigurePrimaryHttpMessageHandler(() => upstream);

outcome.ShouldBeOk();
upstream.Attempts.Should().Be(2);   // exactly one retry, as a number
```

Run `nix develop .#ci -c ./scripts/ci/pkg-validate.sh` to pack both packages,
validate metadata and symbols, and exercise them through a scratch consumer. See
[the library baseline](docs/developer/dotnet-lib-baseline.md) for release and
promotion guidance.
