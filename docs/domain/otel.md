# Ubiquitous language: Otel

The observability engine. It owns the canonical `otel:` block, the mapping from
service-tree identity to OpenTelemetry resource attributes, host wiring for all
three signals, and the concrete emit seams.

| Term                   | Meaning                                                                 |
| ---------------------- | ----------------------------------------------------------------------- |
| `OtelOption`           | The canonical `otel:` block; the fleet's reference binding.             |
| `SignalOption`         | The shape shared by every signal: an on/off flag and its exporters.     |
| `ExporterOption`       | The console and OTLP exporters available to a signal.                   |
| `SamplerOption`        | The trace sampler selection: a type and a ratio.                        |
| `AppIdentity`          | The five taxonomy values telemetry is attributed to.                    |
| `AtomiResource`        | Maps an identity onto semconv and raw `atomi.*` resource attributes.    |
| `OtelEnvironment`      | Resolves the standard `OTEL_*` overrides against the block.             |
| `ExporterSelection`    | Which exporters a signal writes to after those overrides.               |
| `OtelSampler`          | Maps a `SamplerOption` onto an OpenTelemetry sampler.                   |
| `OtelHostExtensions`   | `AddAtomiOtel`: builds the signal pipelines onto a host.                |
| `Instrumentation`      | The app-scoped `ActivitySource` and `Meter`, named from the identity.   |
| `OtelLoggerSink`       | The `ILoggerSink` implementation.                                       |
| `OtelMetricsCollector` | The `IMetricsCollector` implementation.                                 |
| `ITraceEmitter`        | The language-local trace emit seam.                                     |
| `ActivityTraceEmitter` | The real emitter, over `Instrumentation.ActivitySource`.                |
| `TraceRecord`          | One validated, immutable span: name, attributes, events, status.        |
| `TraceEvent`           | One timestamped annotation inside a span.                               |
| `TraceError`           | The trace seam's failure value; emitting never throws.                  |
| `TraceAttributes`      | The attribute-map invariants every trace record shares.                 |
| `TraceWire`            | The lowercase-hyphen wire names of the trace enumerations.              |
| `OtelBlockSchema`      | The engine-owned JSON Schema for the block, consumed by the config lib. |

## Ownership boundaries

**The engine owns its own block schema.** The config library merges and validates
a service-composed root; it does not know these keys. `OtelBlockSchema.Json` is
how it learns them.

**The engine owns its own identity input.** `AppIdentity` is deliberately not
`AppOption` from the config library: this engine needs five taxonomy values, and
depending on the config library to obtain them would invert the dependency. The
config library remains the sole merger and validator.

**The trace seam is language-local.** `ILoggerSink` and `IMetricsCollector` are
declared in `AtomiCloud.Diene.Interfaces` because a log record and a metric sample
are the same shape in every language. A span is not: it carries events, status,
and nesting that each runtime models differently, so every language owns the
emitter it can honestly implement.

**The TestHelper ships the trace double only.** `InMemoryLoggerSink` and
`InMemoryMetricsCollector` live in `AtomiCloud.Diene.Interfaces.TestHelper`,
because a consumer asserting on emitted logs needs them whether or not an
OpenTelemetry pipeline is in play. Re-mocking them here would create two mocks
that could disagree.

## Invariants

- **Off by default.** Every exporter ships disabled; a landscape overlay turns one
  on. A service that forgets to configure an overlay emits nothing.
- **`http/protobuf` on 4318, fleet-wide.** The protocol is pinned in the options
  and validated; gRPC and 4317 are rejected. An enabled OTLP exporter must name a
  non-blank absolute http(s) endpoint with port 4318 EXPLICIT — an implicit 80/443
  is refused — unless `OTEL_EXPORTER_OTLP_ENDPOINT` supplies it instead.
- **Durations are ISO 8601 strings.** `interval` and `timeout` are parsed through
  core-utils `Wire.ParseDuration`; raw millisecond integers are rejected, as are
  zero, negative, and durations beyond the millisecond range the SDK accepts.
- **Plan before register.** The whole block is validated before the host is
  mutated, so a failure in any signal leaves no pipeline and no seam behind
  rather than a half-wired host whose startup then fails.
- **Environment wins over block.** `OTEL_SDK_DISABLED` beats everything; the
  per-signal exporter variables are set-membership, so `none` silences a signal
  and an unrecognized name turns both exporters off.
- **Resource attributes are derived.** Each identity value lands on its semconv
  key and its raw `atomi.*` key. `atomi.module` has no semconv twin because the
  taxonomy is finer-grained than semconv.
- **Emitting is total.** Every seam method returns a `Result` and never throws:
  telemetry can never be the reason a business operation fails.
- **Trace records are validated and immutable.** Attribute keys are non-blank and
  NUL-free, real values are finite, keys are sorted, and two records carrying the
  same attributes compare equal regardless of insertion order.
- **No per-instrument toggles.** Auto-instrumentation is on when the signal is on.

Use "block", "signal", "exporter", "sampler", "resource attribute", "identity",
"seam", "span", and "emit" consistently.
