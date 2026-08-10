# AtomiCloud.Diene.CoreUtils

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

[![CI](https://github.com/AtomiCloud/diene.dotnet-core-utils/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.dotnet-core-utils/actions/workflows/ci.yaml)
[![Unit coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-core-utils/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.dotnet-core-utils)
[![Integration coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-core-utils/graph/badge.svg?flag=int)](https://codecov.io/gh/AtomiCloud/diene.dotnet-core-utils)
[![Commit activity](https://img.shields.io/github/commit-activity/m/AtomiCloud/diene.dotnet-core-utils)](https://github.com/AtomiCloud/diene.dotnet-core-utils/commits/main)

This branch adds the .NET 10 toolchain, the `App`/`Lib`/`UnitTest`/`IntTest`
sample, merged multi-project coverage, strict and LLM dead-code modes. See [the .NET baseline](docs/developer/dotnet-baseline.md).

Common commands:

- `task build`, `task dev`, `task run`, and `task preview`
- `task test`, `task test:unit`, `task test:int`, and the coverage variants
- `task deadcode` for the non-blocking review; CI owns strict dn-inspect

The wire contract, slug parity rules, and key-matching rule are documented in
[docs/domain/core-utils.md](docs/domain/core-utils.md).
Production observability is intentionally absent until the observability add-back.

<!-- ### dotnet-lib -->
<!-- #### source: dotnet-lib -->

## Publishable library packages

[![NuGet version](https://img.shields.io/nuget/v/AtomiCloud.Diene.CoreUtils)](https://www.nuget.org/packages/AtomiCloud.Diene.CoreUtils)
[![NuGet downloads](https://img.shields.io/nuget/dt/AtomiCloud.Diene.CoreUtils)](https://www.nuget.org/packages/AtomiCloud.Diene.CoreUtils)

This repository publishes one package, `AtomiCloud.Diene.CoreUtils`. It holds the
three things the .NET family could not take from the BCL: the C0 §1 wire codecs,
slug and namespaced-key helpers that are byte-parity with the TypeScript sibling,
and the canonical key-matching rule the Config lib consumes.

There is deliberately **no TestHelper companion** — every member is a
deterministic value function with no port to fake and no assertion worth
re-shipping. `pls test:meta` is a no-op here and no empty `meta` flag is uploaded.
The shipped usage skill carries the how-to-add-one-later guidance.

```bash
dotnet add package AtomiCloud.Diene.CoreUtils
```

```csharp
using System.Text.Json;
using AtomiCloud.Diene.CoreUtils;
using AtomiCloud.Diene.CoreUtils.Json;

// One registration puts every temporal, decimal, and int64 on the wire in C0 form.
var json = JsonSerializer.Serialize(receipt, AtomiJson.DefaultOptions);
// {"shippedOn":"2026-07-25","confirmedAt":"2026-07-25T22:30:00Z",
//  "transitTime":"PT1H30M","originZone":"Asia/Singapore","declaredValue":"1249.50"}

// Result-returning codecs for the call sites that are not JSON.
Wire.ParseTimeZone("Singapore Standard Time");  // Err — IANA ids only
Wire.Format(TimeSpan.FromMinutes(90));          // "PT1H30M"

Slug.NamespacedKey("AtomiCloud", "Express Parcel");  // Ok("atomicloud:express-parcel")
KeyNormalizer.KeysMatch("error_portal", "ErrorPortal");  // true
```

This package consumes the published `AtomiCloud.Diene.Result` and
`AtomiCloud.Diene.Interfaces` packages from nuget.org — never a project
reference. The root `NuGet.config` clears every source but nuget.org so that
stays true.

Run `nix develop .#ci -c ./scripts/ci/pkg-validate.sh` to pack the package,
validate metadata and symbols, and restore it into a scratch consumer. See
[the library baseline](docs/developer/dotnet-lib-baseline.md) for release and
promotion guidance.
