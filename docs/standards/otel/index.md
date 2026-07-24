# OpenTelemetry

`@atomicloud/diene.otel` owns the Bun family's OpenTelemetry wiring: the engine-owned
configuration block schema, the canonical resource identity, the signal lifecycle, the
standard-environment override behavior, the pino logging bridge, and the language-local
trace seam. It ships the schema, the SDK-backed implementations, and framework-free
telemetry test doubles. It ships no service configuration loader and chooses no landscape
endpoints.

This article is the Bun implementation of the shared **O1 OpenTelemetry Alignment
Contract**, the same contract `lib/dotnet/otel` and `lib/go/otel` implement. It builds on
[Three-Layer Architecture](../three-layer-architecture/index.md),
[Functional practices](../functional-practices/index.md),
[Stateless OOP and dependency injection](../stateless-oop-di/index.md),
[Service-tree identity](../service-tree/index.md), and
[Data validation](../validation/index.md).

---

## Canonical block

The configuration shape is dotnet-priority: bindable nested booleans, no exporter enum
strings, and identical exporter sub-blocks per signal. Signal keys are exactly `logs`,
`metrics`, and `traces`.

```yaml
otel:
  logs:
    enabled: true
    exporter:
      console:
        enabled: false
      otlp:
        enabled: false
        endpoint: ''
        protocol: http/protobuf
        headers: {}
        timeout: PT10S
  metrics:
    enabled: true
    exporter:
      console:
        enabled: false
      otlp:
        enabled: false
        endpoint: ''
        protocol: http/protobuf
        headers: {}
        timeout: PT10S
    interval: PT60S
  traces:
    enabled: true
    sampler:
      type: parentbased_traceidratio
      ratio: 1.0
    exporter:
      console:
        enabled: false
      otlp:
        enabled: false
        endpoint: ''
        protocol: http/protobuf
        headers: {}
        timeout: PT10S
```

The base block enables the signal pipelines but keeps every exporter **off**. A landscape
overlay flips the exporter it needs on and supplies the endpoint — the base file never
carries a concrete endpoint. This is the **off-by-default, landscape-flip** convention: an
application ships dark and a landscape lights it up without a new release.

### Frozen invariants

- Signal keys are exactly `logs`, `metrics`, and `traces`.
- Exporter selection is independent per-exporter `enabled` booleans — there is no `use` or
  `exporterType` enum.
- OTLP is **HTTP/protobuf on port 4318** fleet-wide.
- Durations are ISO-8601 strings (`PT10S`, `PT60S`), parsed via
  `@atomicloud/diene.core-utils` `parseWireDuration` (Temporal). A duration must be a
  positive, fixed-length canonical ISO-8601 duration.
- `traces.sampler.type ∈ { parentbased_traceidratio, always_on, always_off }`; `ratio` is
  finite and in the inclusive range `[0, 1]`. Out-of-range or `NaN` ratios are **rejected**.
- Disabled signals and disabled/empty exporters construct **no** network clients, exporters,
  processors, readers, or background timers.
- An **enabled** OTLP exporter with an empty `endpoint` **fails validation before startup**.

The schema is engine-owned: this package exports the zod block schema and the inferred
types, and it validates its own block shape only. It never loads files.

---

## Resource identity (R14)

Every implementation derives resource attributes from the validated `app:` service-tree
block; consumers never hand-author them. The mapping is fixed:

| Service-tree value | Semantic convention           |
| ------------------ | ----------------------------- |
| landscape          | `deployment.environment.name` |
| platform           | `service.namespace`           |
| service            | `service.name`                |
| version            | `service.version`             |

All five raw taxonomy values are also emitted under the `atomi.*` namespace:

- `atomi.landscape`
- `atomi.platform`
- `atomi.service`
- `atomi.module`
- `atomi.version`

The programmatic resource only **augments**. It sets a key only when
`OTEL_RESOURCE_ATTRIBUTES` / `OTEL_SERVICE_NAME` do not already claim it — the environment
wins (see below).

---

## Standard `OTEL_*` environment variables win

The library configures the SDK programmatically **only when the corresponding standard
`OTEL_*` variable is unset**, and never clobbers a variable an operator set. This covers
exporter endpoints, headers, resource attributes, sampler settings, and
`OTEL_SDK_DISABLED`. Operations must be able to override the block without a new application
release.

- If `OTEL_TRACES_SAMPLER` is set, the library omits the programmatic sampler entirely and
  lets the SDK consume `OTEL_TRACES_SAMPLER` / `OTEL_TRACES_SAMPLER_ARG`.
- If `OTEL_SDK_DISABLED` is set truthy, init is a whole no-op — no pipelines are built.
- `OTEL_EXPORTER_OTLP_*` variables suppress the matching programmatic exporter option.

---

## Ownership and composition

Three surfaces, three owners — keep them separate:

| Surface                                              | Owner                                   |
| ---------------------------------------------------- | --------------------------------------- |
| OTel block types and schema                          | this package (`@atomicloud/diene.otel`) |
| YAML/env loading, merge order, final root validation | `@atomicloud/diene.config`              |
| Infra presets (postgres, kv, cache, storage)         | `standard-config`, never OTel           |
| Logging and metrics emit seams                       | `@atomicloud/diene.interfaces`          |
| Trace / span seam and its test double                | this package (RB-19)                    |
| SDK-backed implementations                           | this package                            |
| Consumer lifecycle wiring and real-export SIT        | the consumer / service                  |

A service imports this schema into its composed root schema in **one line**; `standard-config`
must not duplicate or wrap the block. `lib/bun/config` is the sole merger and final validator.

---

## Signal lifecycle and public capabilities

The library provides exactly these capabilities, and no more:

1. Validate the engine-owned block.
2. Build the canonical resource from `app:`.
3. Return one initialized runtime for the consumer to retain; the consumer calls init once and
   reuses that runtime rather than constructing competing global providers.
4. Expose service-scoped `logger`, `meter`, and `tracer` accessors, plus the family-interface
   implementations (`LoggerSink`, `MetricsCollector`) and this package's trace emitter.
5. Expose an explicit `flush` / `shutdown` operation.
6. Register **no** process signal handlers. The consumer owns `SIGTERM` and calls flush /
   shutdown itself.

Init returns accessors and a flush regardless of configuration; when a signal has no selected
exporter, the accessor is a no-op flavor and no provider, exporter, reader, processor, timer,
or network client is constructed.

### Traces and metrics

- **Traces** use a hand-assembled tracer provider with the canonical resource, the mapped
  sampler, and a batch span processor over the OTLP/protobuf trace exporter — built only when
  `traces.enabled && traces.exporter.otlp.enabled`. A console exporter sits behind
  `exporter.console.enabled`. The granular `@opentelemetry/sdk-trace-*` APIs are used rather
  than `NodeSDK`, so the `OTEL_*`-wins law stays under the library's control.
- **Sampler mapping**: `parentbased_traceidratio` →
  `ParentBasedSampler({ root: TraceIdRatioBasedSampler(ratio) })`; `always_on` → `AlwaysOnSampler`;
  `always_off` → `AlwaysOffSampler`. When `OTEL_TRACES_SAMPLER` is set, no programmatic sampler
  is passed.
- **Metrics** use a meter provider with a periodic exporting reader over the OTLP/protobuf
  metric exporter (export interval from `metrics.interval`) when OTLP is enabled, and a console
  reader behind the console flag.

### Logs (S23): pino with a stubbed OTLP bridge

The Bun wrapper logs through **pino** — JSON to stdout, scraped by Alloy — with OpenTelemetry
trace-context injection (a mixin that pulls `trace_id`, `span_id`, and `trace_flags` from the
active span context). The **OTLP logs bridge is explicitly stubbed** in v1: the package takes
no `@opentelemetry/sdk-logs` dependency and exposes a documented no-op for the OTLP logs path,
recorded as "stubbed until the JS SDK logs signal is 1.0-ready". Metrics and traces use OTLP;
logs reach the backend through the pino → Alloy path.

---

## Trace seam ownership (RB-19)

Trace and span contracts are **language-local to this package**. Per RB-19,
`@atomicloud/diene.interfaces` has no trace port and `PortName` has no `tracing` member — the
interfaces package owns only the `LoggerSink` and `MetricsCollector` effect seams. This package
therefore defines its own idiomatic trace-emitter interface (span start / end / event / status
over `TelemetryAttributes`), its own error tag, its in-memory trace double, and it documents
trace testing here. Do not ask the interfaces package to add a trace seam.

This package **implements** `LoggerSink` (pino-backed) and `MetricsCollector` (SDK-backed),
both returning `Result<void, PortError>` and running the shared interface validators first, so
a real adapter rejects exactly what the interfaces mock rejects.

---

## Evidence boundary and test-helper use

Unit tests transcribe the canonical block above into accept / reject fixtures and cover
resource mapping, sampler mapping, and disabled-exporter no-op behavior. Integration tests use
**in-memory telemetry seams and never start a fake collector or open a network client**. Real
`:4318` export is a consumer-owned SIT journey through the configured Alloy path, not a gate on
this package.

Framework-free telemetry test doubles ship at `@atomicloud/diene.otel/test-helper`:

- **Consume, do not re-implement**, the interfaces doubles for logging and metrics —
  `InMemoryLoggerSink`, `InMemoryMetricsCollector`, and their assertions come from
  `@atomicloud/diene.interfaces/test-helper`.
- **Owned here (RB-19)**: `InMemoryTraceEmitter` plus OTel-specific resource and payload
  asserters (for example span-record and resource-attribute assertions). The helpers record
  validated interactions deterministically, enforce the same invariants as the real path, and
  fail with precise messages.
- Supplying a seam override selects it before signal construction. The corresponding real
  provider, exporter, reader, processor, registration, or pino output is not created, even if
  that signal's OTLP exporter is enabled in the block.
- The package's own meta tier proves every shipped assertion both fails on a known-bad emission
  and passes on a known-good one, and runs a shared behavioral suite against the real SDK-backed
  implementation and the in-memory double where the no-collector boundary allows.

When a consumer needs a fake logger or metrics collector, it imports those from the interfaces
test-helper; when it needs to assert traces or resource identity, it uses this package's
test-helper. There is one coherent public seam and mock story across the two packages.
