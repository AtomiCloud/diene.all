---
name: diene-dotnet-otel-usage
description: Wire OpenTelemetry logs, metrics, and traces onto a .NET host from the canonical otel config block, map service-tree identity onto semconv resource attributes, implement or consume the ILoggerSink/IMetricsCollector/ITraceEmitter seams, and assert emitted spans with AtomiCloud.Diene.Otel.
---

# Diene .NET otel usage

## What these packages are

`AtomiCloud.Diene.Otel` is the observability ENGINE. It owns four things:

1. The canonical `otel:` config block — these Options classes ARE the reference
   binding for the whole fleet.
2. The mapping from service-tree identity to OpenTelemetry resource attributes.
3. Host wiring for all three signals, including `OTEL_*` environment precedence.
4. The concrete `ILoggerSink` / `IMetricsCollector` implementations plus a
   language-local trace seam.

`AtomiCloud.Diene.Otel.TestHelper` ships the TRACE seam double only. Logging and
metrics mocks live in `AtomiCloud.Diene.Interfaces.TestHelper` — do not look for
them here and do not write your own.

## Install

```bash
dotnet add package AtomiCloud.Diene.Otel
dotnet add package AtomiCloud.Diene.Otel.TestHelper   # test projects only
```

## The canonical block

Everything is OFF unless a landscape overlay turns it on. A service that forgets
to configure an overlay emits nothing rather than spraying spans at stdout in
production.

```yaml
otel:
  logs:
    enabled: true
    exporter:
      console: { enabled: false }
      otlp:
        enabled: false
        endpoint: '' # e.g. http://collector:4318
        protocol: http/protobuf # pinned fleet-wide
        headers: {}
        timeout: PT10S
  metrics:
    enabled: true
    interval: PT60S
    exporter: { console: { enabled: false }, otlp: { enabled: false } }
  traces:
    enabled: true
    sampler:
      type: parentbased_traceidratio # | always_on | always_off
      ratio: 1.0
    exporter: { console: { enabled: false }, otlp: { enabled: false } }
```

`timeout` and `interval` are ISO 8601 duration STRINGS (C0 §1), parsed through
core-utils `Wire.ParseDuration`. A raw millisecond integer is rejected.

## Environment overrides

Ops must be able to redirect or silence telemetry without a redeploy, so the
standard variables win over the block:

| Variable                              | Effect                                                    |
| ------------------------------------- | --------------------------------------------------------- |
| `OTEL_SDK_DISABLED=true`              | Wins over everything; no signal is built                  |
| `OTEL_{LOGS,METRICS,TRACES}_EXPORTER` | Unset/blank ⇒ block; `none` ⇒ silent; else set membership |
| `OTEL_EXPORTER_OTLP_ENDPOINT`         | The block's `endpoint` is skipped entirely                |
| `OTEL_RESOURCE_ATTRIBUTES`            | Merged over the derived attributes                        |
| `OTEL_SERVICE_NAME`                   | Overrides `service.name`, beating the list above          |
| `OTEL_TRACES_SAMPLER`                 | The programmatic sampler is skipped; the SDK's own wins   |

An override that names neither exporter (`OTEL_LOGS_EXPORTER=jaeger`) turns both
off — set membership, not a fallback.

## Quickstart

```csharp
var builder = Host.CreateApplicationBuilder(args);

var identity = AppIdentity
    .Create(landscape, platform, service, module, version)
    .Get();   // check this Result; a blank field is rejected

builder.AddAtomiOtel(identity, builder.Configuration)
    .Match(_ => { }, error => throw new InvalidOperationException(error.ToString()));

using var host = builder.Build();
```

`AddAtomiOtel` returns `Result<Unit, TraceError>` — a bad duration or sampler is a
value, not an exception thrown out of your startup path. Decide deliberately
whether a malformed block should stop the process.

It registers `AppIdentity`, `Instrumentation`, `ILoggerSink`, `IMetricsCollector`,
and `ITraceEmitter` as singletons, so inject the seam, never the SDK.

## Resource mapping

Resource attributes are always DERIVED from the identity, never hand-authored.
Each value lands on its semconv key AND its raw `atomi.*` key, so a query can use
either vocabulary.

| Identity    | semconv key                   | raw key           |
| ----------- | ----------------------------- | ----------------- |
| `landscape` | `deployment.environment.name` | `atomi.landscape` |
| `platform`  | `service.namespace`           | `atomi.platform`  |
| `service`   | `service.name`                | `atomi.service`   |
| `version`   | `service.version`             | `atomi.version`   |
| `module`    | — (no semconv twin)           | `atomi.module`    |

`atomi.module` deliberately has no semconv key: the taxonomy is finer-grained
than semconv, and inventing `service.module` would be a fleet-local fiction.

## Using the seams

```csharp
public sealed class Checkout(ILoggerSink logger, IMetricsCollector metrics, ITraceEmitter traces)
{
    public Result<Unit, SeamError> Complete(decimal amount)
    {
        var attributes = new Dictionary<string, AttributeValue>(StringComparer.Ordinal)
        {
            ["currency"] = AttributeValue.Text("SGD"),
        };

        logger.Emit(new LogRecord(DateTimeOffset.UtcNow, LogLevel.Info, "checkout complete", attributes));
        metrics.Emit(new MetricRecord(DateTimeOffset.UtcNow, "checkout.completed", MetricKind.Counter, 1, "1", attributes));

        TraceRecord
            .Create("checkout.complete", attributes, status: TraceStatus.Ok)
            .Then(traces.Emit);

        return Result.Ok<Unit, SeamError>(default);
    }
}
```

Every emit is TOTAL: it returns a Result and never throws, so telemetry can never
be the reason a business operation fails. Attribute values travel in their C0 wire
form, so what you emit is byte-identical to what a reader sees.

Trace records are validated at construction: attribute keys are non-blank and
NUL-free, real values must be finite, keys are sorted, and the record is immutable
afterwards. Two records carrying the same attributes compare equal regardless of
the order you supplied them in.

## TestHelper (trace seam only)

```csharp
var traces = new InMemoryTraceEmitter();
var logger = new InMemoryLoggerSink();          // from Interfaces.TestHelper
var metrics = new InMemoryMetricsCollector();   // from Interfaces.TestHelper

new Checkout(logger, metrics, traces).Complete(12.50m).Should().BeOk();

traces.Should().HaveEmitted("checkout.complete")
    .Which.Should().HaveStatus(TraceStatus.Ok)
    .And.HaveAttribute("currency", AttributeValue.Text("SGD"));
logger.Should().HaveLogged(LogLevel.Info, "checkout complete");
```

Drive the unhappy path with scripted failures rather than a mocking framework:

```csharp
traces.FailNext(TraceErrors.Io("emit", "exporter refused"));
subject.Complete(12.50m).Should().BeTraceErr(TraceErrorCode.Io);
traces.Calls.Should().ContainSingle();   // the attempt is recorded even though it failed
```

`Calls` records every call including the failures, so you can assert what the
subject TRIED to emit, not only what got through. `Records` holds only the
accepted spans.

## Do

- Ship with every exporter OFF and let the landscape overlay turn one on.
- Use `http/protobuf` on port **4318**. It is pinned fleet-wide.
- Inject `ILoggerSink` / `IMetricsCollector` / `ITraceEmitter`, not the SDK types.
- Check the `Result` from `AddAtomiOtel` and from every emit.
- Get logging and metrics mocks from `AtomiCloud.Diene.Interfaces.TestHelper`.

## Do not

- Do not add per-instrument toggles. Auto-instrumentation is on when the signal
  is on; a matrix of sub-switches is drift waiting to happen.
- Do not use gRPC or port 4317 (the `zinc` drift this package exists to end).
- Do not put a raw millisecond integer where a duration belongs.
- Do not write your own logging or metrics mock.
- Do not hand-author resource attributes; derive them from `AppIdentity`.
- Do not call `.Get()` on a Result without checking — use `Match`, `Then`, `Map`.

## Verify your wiring

```bash
dotnet build                     # zero warnings; warnings are errors
pls test:unit:coverage           # 100% on the shipped assembly
pls test:meta                    # assert-the-asserter + trace parity
pls test:int:coverage            # host-level wiring, no collector needed
```

To confirm a signal actually reaches a collector, set
`OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_TRACES_EXPORTER=otlp` and watch the
collector — not the application logs.

For package lifecycle, identity, coverage, and promotion rules, read
`docs/developer/dotnet-lib-baseline.md` in the source repository.
