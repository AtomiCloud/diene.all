---
name: diene-dotnet-interfaces-usage
description: Use AtomiCloud.Diene.Interfaces seams, their in-memory mocks, and the shared contract suites in a .NET consumer.
---

# Diene .NET interfaces usage

## What this package is

`AtomiCloud.Diene.Interfaces` DECLARES the shared seams — `ISystem`, `IVfs`,
`ITerminal`, `ILoggerSink`, `IMetricsCollector` — and ships nothing concrete.
Depend on the seam, never on `System.IO`, `System.Diagnostics.Process`, or
`System.Environment`, in any code you intend to test.

## The failure model

Every fallible method returns `Result<T, SeamError>`. It never throws and never
captures. Match on `SeamError.Id` from the `SeamErrors` catalog — `not_found`,
`already_exists`, `not_a_directory`, `directory_not_empty`, `io_failure`,
`invalid_argument`, `environment_unavailable`, `launch_failed`, `emit_failed`,
`cancelled`, `invalid_wire`, `unknown_time_zone`.

```csharp
var read = await vfs.ReadText(path);
return read.Match(
    text => Parse(text),
    error => error.Id == "not_found" ? Defaults() : Result.Err<Config, SeamError>(error));
```

Do NOT wrap seam calls in `try`/`catch` to convert exceptions — there are none to
catch. Do NOT call `Get()` without first checking `IsSuccess`; use `Match`,
`Then`, `Map`, or `GetOr`.

A non-zero child exit code is a SUCCESSFUL `TerminalOutput` with
`Succeeded == false`. Only a launch failure is a `SeamError`. Do not treat exit
code 1 as an error channel.

## Wire formats

Values that cross the wire obey C0: RFC 3339 UTC instants, ISO 8601 durations,
IANA timezone ids, and one lowercase wire name per enumeration. Use `SeamWire`
and `AttributeValue` for those conversions; never hand-format a timestamp or a
duration, and never use `DateTime` where a `DateTimeOffset` is expected.

```csharp
var attributes = new Dictionary<string, AttributeValue>(StringComparer.Ordinal)
{
    ["route"] = AttributeValue.Text("/v1/notes"),
    ["elapsed"] = AttributeValue.Duration(elapsed),
    ["retried"] = AttributeValue.Flag(true),
};
logger.Emit(new LogRecord(now, LogLevel.Info, "request served", attributes));
```

## TestHelper usage

`AtomiCloud.Diene.Interfaces.TestHelper` ships the in-memory mock for every seam
declared here — including the logging and metrics sinks. Reach for
`Otel.TestHelper` only when you are testing an OpenTelemetry pipeline itself.

```csharp
var system = new InMemorySystem(now: anchor, environment: [new("ATOMI_LANDSCAPE", "lapras")]);
var vfs = new InMemoryVfs();
var logger = new InMemoryLoggerSink();

vfs.Seed("/etc/app.yaml", "key: value");
var subject = new MyLoader(system, vfs, logger);

(await subject.Load()).Should().BeOk();
logger.Should().HaveLogged(LogLevel.Info, "config loaded");
```

Drive the unhappy path with the fault queue instead of a mocking framework:

```csharp
vfs.EnqueueFailure(SeamErrors.IoFailure(SeamKind.Vfs, "read", "disk full"));
(await subject.Load()).Should().BeSeamErr(SeamKind.Vfs, "io_failure");
```

`BeSeamErr` extends the published `AtomiCloud.Diene.Result.TestHelper`
assertions, so keep one `Should()` entry point for Results and add
`using AtomiCloud.Diene.Results.TestHelper;` alongside this package.

## Proving your own implementation

If you write a real adapter, prove it against the shipped suite rather than
inventing expectations — then run the same suite against the mock you substitute
for it. That pairing is the contract-parity guarantee.

```csharp
(await SeamContracts.Vfs(new MyVfs(), scratchRoot)).Should().BeConformant();
(await SeamContracts.Vfs(new InMemoryVfs(), "/scratch")).Should().BeConformant();
```

`ContractReport.Failures` names each failed case, so a red suite tells you which
behaviour diverged.

## Coverage placement

The TestHelper assembly is test infrastructure: measure it through the meta tier
(`pls test:meta`), never the unit ledger. Extend an assertion helper only with a
known-good AND a known-bad case.

For package lifecycle, identity, coverage, and promotion rules, read
`docs/developer/dotnet-lib-baseline.md` in the source repository.
