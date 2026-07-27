---
name: diene-go-otel-usage
description: Configure and bootstrap Diene's Go OpenTelemetry engine, emit logs, metrics, and traces, and test telemetry with its in-memory TestHelper doubles. Use when a Go service consumes github.com/AtomiCloud/diene.go-otel, composes the canonical C0 otel block, maps service identity to resource attributes, honors OTEL_* overrides, or needs collector-free telemetry tests.
---

# Diene Go OpenTelemetry usage

Import the pure contract from
`github.com/AtomiCloud/diene.go-otel/lib/otel`, SDK wiring from
`github.com/AtomiCloud/diene.go-otel/adapters/otelsdk`, and consumer test
doubles from `github.com/AtomiCloud/diene.go-otel/testhelper`.

## Configure and bootstrap

1. Compose `otel.JSONSchema()` under `otel.SchemaKey()` in the service's root
   configuration schema. Keep merging and strict decoding in the configuration
   layer; this module owns only the block contract and validation.
2. Start from `otel.DefaultConfig()`. Exporters are off by default. Enable an
   OTLP exporter only through a landscape overlay and use an HTTP(S) endpoint
   with explicit port `4318`; the protocol is always `http/protobuf`.
3. Supply every `otel.AppIdentity` coordinate. Derive resource attributes with
   `otel.ResourceAttributes`; never hand-author the semconv or `atomi.*` map.
4. Build one `otelsdk.Runtime` at application boot. Keep global provider
   registration off in libraries; applications may opt in once with
   `otelsdk.WithGlobalRegistration(true)`.
5. Defer `Runtime.Shutdown`. Use `Runtime.LoggerSink`, `MetricsCollector`, and
   `TraceEmitter` for the shared emission surface. Bind request context with
   `Runtime.LoggerSinkContext` or `TraceEmitter.EmitContext` when correlation is
   required.

Copy and adapt [assets/canonical-config.yaml](assets/canonical-config.yaml) and
[assets/bootstrap.go.txt](assets/bootstrap.go.txt). `OTEL_SDK_DISABLED` always wins;
set `OTEL_*` values remain authoritative over block-derived SDK options.

## Test all three signals without infrastructure

Inject `testhelper.NewInMemoryLoggerSink`,
`testhelper.NewInMemoryMetricsCollector`, and
`testhelper.NewInMemoryTraceEmitter` through the matching `otelsdk.With*`
options. Assert exact records with `AssertLogRecords`, `AssertMetricRecords`,
and `AssertTraceRecords`. Script deterministic failures with `EnqueueResult`.

For traces specifically (RB-19), inject
`testhelper.NewInMemoryTraceEmitter`, emit an `otel.TraceRecord`, and call
`testhelper.AssertTraceRecords`. Never start an OTLP collector, container, fake
telemetry service, or network listener in unit, integration, or meta tests.
Copy [assets/trace_test.go.txt](assets/trace_test.go.txt) as the canonical pattern.

Use `Check*` assertions when the caller needs an error instead of a fatal test
failure. Treat every non-nil engine error as problem-typed and inspect it with
`errors.As` or `testhelper.CheckProblemFault`.

Before changing an exported API, run `./scripts/ci/pkg-validate.sh all`. Keep v1
changes backward compatible; an intentional breaking release needs a reviewed
`/v2` module-path migration.
