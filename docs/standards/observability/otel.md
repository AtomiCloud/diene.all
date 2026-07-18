# OpenTelemetry Alignment Contract

This is the shared O1 contract for `lib/bun/otel`, `lib/dotnet/otel`, and
`lib/go/otel`. Each library owns its language implementation and engine-owned
schema, but all three expose the same configuration concepts, resource identity,
override behavior, lifecycle, and test boundary. Dart is frontend-only and uses
[Faro](./faro.md) instead of a Dart OTel runtime library.

## Canonical block

The configuration shape is dotnet-priority: bindable nested booleans, no
exporter enum strings, and identical exporter sub-blocks per signal.

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

The base file enables the signal pipelines but keeps exporters off. A landscape
overlay enables the required exporter and supplies its endpoint. O1 does not
choose concrete landscape endpoints.

Required invariants:

- Signal keys are exactly `logs`, `metrics`, and `traces`.
- Exporter selection uses independent `enabled` booleans.
- OTLP is HTTP/protobuf on port 4318 fleet-wide.
- Durations use ISO 8601 strings.
- The sampler names are `parentbased_traceidratio`, `always_on`, and
  `always_off`; ratio is in the inclusive range 0–1.
- Empty or disabled exporters create no network clients or background workers.
- A configured exporter with a missing endpoint fails validation before startup.

## Ownership and composition

| Surface                                                  | Owner                                    |
| -------------------------------------------------------- | ---------------------------------------- |
| OTel block types and schema                              | The language's OTel library              |
| YAML/env loading, merge order, and final root validation | The language's config library            |
| Infra presets such as postgres/kv/cache/storage          | `standard-config`, never OTel            |
| Logging and metrics emit seams                           | The language's common interfaces library |
| SDK-backed implementations                               | The language's OTel library              |
| Consumer lifecycle wiring and real-export SIT            | The consumer/service                     |

A service imports the OTel schema into its composed root schema in one line.
`standard-config` must not duplicate or wrap the block.

## Resource identity

Every implementation derives resource attributes from the validated `app:`
service-tree block. Consumers never hand-author these attributes.

| Service-tree value | Semantic convention           |
| ------------------ | ----------------------------- |
| landscape          | `deployment.environment.name` |
| platform           | `service.namespace`           |
| service            | `service.name`                |
| version            | `service.version`             |

All five raw taxonomy values are also emitted:

- `atomi.landscape`
- `atomi.platform`
- `atomi.service`
- `atomi.module`
- `atomi.version`

## Standard OTel environment variables win

The libraries configure SDKs programmatically only when the corresponding
standard `OTEL_*` environment variable is unset. This includes exporter
endpoints, headers, resource attributes, propagators, sampler settings, and
`OTEL_SDK_DISABLED`. Operations must be able to override the block without a
new application release.

## Lifecycle and public capabilities

All three libraries provide the same conceptual capabilities:

1. Validate the engine-owned block.
2. Build the canonical resource from `app:`.
3. Initialize enabled signal pipelines exactly once.
4. Expose service-scoped logger, meter, and tracer accessors or implementations
   of the family interfaces.
5. Expose an explicit flush/shutdown operation.
6. Avoid registering process signal handlers; the consumer owns lifecycle
   hooks and invokes flush/shutdown.

The language wrappers stay outside the canonical block:

- Bun uses pino with trace-context injection and JSON stdout to Alloy. Metrics
  and traces use OTLP; the Bun v1 OTLP logs bridge remains explicitly stubbed.
- .NET uses `Microsoft.Extensions.Logging` and native OpenTelemetry hosting
  integration.
- Go uses `slog` and the native OpenTelemetry SDK.

## Evidence boundary

Unit tests use shared C0 fixtures for schema acceptance/rejection, resource
mapping, sampler mapping, and disabled-exporter behavior. Integration tests use
in-memory telemetry seams; they never start a fake collector. Real export is a
consumer-owned SIT journey through the configured Alloy path.

The exact S33 split between common-interface mocks, any trace-specific seam,
and each OTel TestHelper is implementation-gated. This contract requires one
coherent public seam and mock story, but does not pre-judge that ownership
decision.
