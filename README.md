# Diene .NET E2e

[![NuGet version](https://img.shields.io/nuget/v/AtomiCloud.Diene.E2e)](https://www.nuget.org/packages/AtomiCloud.Diene.E2e)
[![NuGet downloads](https://img.shields.io/nuget/dt/AtomiCloud.Diene.E2e)](https://www.nuget.org/packages/AtomiCloud.Diene.E2e)
[![CI](https://github.com/AtomiCloud/diene.dotnet-e2e/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.dotnet-e2e/actions/workflows/ci.yaml)
[![Unit coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-e2e/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.dotnet-e2e)
[![Integration coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-e2e/graph/badge.svg?flag=int)](https://codecov.io/gh/AtomiCloud/diene.dotnet-e2e)
[![Meta coverage](https://codecov.io/gh/AtomiCloud/diene.dotnet-e2e/graph/badge.svg?flag=meta)](https://codecov.io/gh/AtomiCloud/diene.dotnet-e2e)

`AtomiCloud.Diene.E2e` is the black-box/SIT harness and compatibility train for
the ten published Diene .NET libraries. It selects an explicit service venue,
drives an ASP.NET application in-process through `WebApplicationFactory`, or
targets a validated Garden preview hostname over HTTP.

`AtomiCloud.Diene.E2e.TestHelper` carries the helper packages that really exist:
Result, Interfaces, Config, Problems, Otel, AuthEngine, StandardConfig,
ApiEngine, and ServerEngine. CoreUtils deliberately has no TestHelper.

```bash
dotnet add package AtomiCloud.Diene.E2e
dotnet add package AtomiCloud.Diene.E2e.TestHelper
```

## Choose the SIT venue

Set `SIT_DRIVER=inprocess` for an in-process service or `SIT_DRIVER=garden` for
a deployed preview environment. The parser refuses an absent or unknown value;
silently choosing a venue would make a green run ambiguous.

```csharp
using AtomiCloud.Diene.E2e.Drivers;

var kind = SitDriverSelection.Resolve(
    Environment.GetEnvironmentVariable(SitDriverSelection.EnvironmentVariable));
```

For an ASP.NET entry point:

```csharp
await using var driver = new InProcessSitDriver<Program>();
using var response = await driver.Client.GetAsync("/system/health");
response.EnsureSuccessStatusCode();
```

For Garden, validate the final service-tree hostname before creating the
driver:

```csharp
using AtomiCloud.Diene.E2e.Garden;

var fixture = new GardenNamespaceFixture(
    "api", "notes", "sulfoxide", "pichu", "mew", "cluster.atomi.cloud");
var endpoint = GardenPreviewEndpoint.Resolve(fixture.Hostname, fixture);
await using var driver = new GardenSitDriver(endpoint);
```

The hostname is always
`module.service.platform.instance.landscape.zone`. HTTPS is the default; HTTP
must be explicit.

## TestHelper bundle

Reference `AtomiCloud.Diene.E2e.TestHelper` only from tests. Its normal NuGet
dependencies expose the nine published helper assemblies without copying their
types or implementations. `ShouldHaveStatus` asserts one exact HTTP status and
returns the response for further body/header checks.

```csharp
using AtomiCloud.Diene.E2e.TestHelper.Assertions;

response.ShouldHaveStatus(HttpStatusCode.MisdirectedRequest);
```

Telemetry integration tests use the Interfaces/Otel in-memory seams. Preview
SIT uses the real environment's Alloy pipeline. This package ships no fake OTLP
collector and no Bruno tooling; Bruno collections belong to the service-side
`dotnet-api` template under `tests/sit/bruno`.

See [the harness contract](docs/domain/e2e.md) and the shipped
[usage skill](skills/diene-dotnet-e2e-usage/SKILL.md).
