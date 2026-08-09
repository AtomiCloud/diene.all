# @atomicloud/diene.otel — patterns

## Do

- Import `otelBlockSchema` from the package root and compose it into your service's
  root schema in one line. Let `lib/bun/config` merge YAML and env and run the final
  validation.
- Keep the base config **off by default**: pipelines enabled, exporters disabled with
  an empty endpoint. Enable an exporter and supply its endpoint in a landscape overlay,
  not in the base file.
- Let standard `OTEL_*` environment variables win. Set exporter endpoints, headers,
  resource attributes, sampler settings, and `OTEL_SDK_DISABLED` through the environment
  in operations; the library only fills in what the environment leaves unset.
- Initialize once, hold the returned accessors and flush, and call flush / shutdown from
  **your** `SIGTERM` handler. The library installs no process hooks.
- Depend on the `LoggerSink` and `MetricsCollector` **contracts** (from
  `@atomicloud/diene.interfaces`) in domain and service code; inject this package's
  SDK-backed implementations at the edge.
- Get trace-context-aware logging from this package's pino bridge; it layers on top of
  the interfaces logging seam rather than replacing it.

The public bootstrap takes the validated block first, the service identity second, and
optional injected seams last:

```ts
const telemetry = initOtel(config.otel, appIdentity, {
  seams: { logger, metrics, traces },
});

await telemetry.flush();
await telemetry.shutdown();
```

Seam overrides are construction guards, not late decorators: an injected seam suppresses the
corresponding real provider/exporter pipeline and active pino output.

## Don't

- Don't deep-import `dist/` internals; only the root entry and the `/test-helper` subpath
  are public.
- Don't rely on import-time side effects — the package is `sideEffects: false`.
- Don't hand-author resource attributes; they are derived from the validated `app:`
  block (R14). Don't override a key the environment already claims.
- Don't wrap the block in `standard-config` or re-declare it there — the schema is owned
  here and merged only by `lib/bun/config`.
- Don't look for an OTLP **logs** exporter — the v1 logs bridge is a documented stub;
  logs reach the backend through pino → Alloy.
- Don't look for a trace port in `@atomicloud/diene.interfaces` — traces are language-local
  to this package (RB-19).
- Don't start a collector or open a network client in tests; use the in-memory seams.

## Test doubles

The telemetry doubles are split across two packages by ownership:

- **Logging and metrics** — `InMemoryLoggerSink`, `InMemoryMetricsCollector`, and their
  assertions ship at `@atomicloud/diene.interfaces/test-helper`. Inject them where init
  wants a `LoggerSink` / `MetricsCollector`; they enforce the same invariants as the real
  path.
- **Traces and OTel identity** — `InMemoryTraceEmitter` and the resource / span asserters
  ship at `@atomicloud/diene.otel/test-helper`. Use them to assert what spans were emitted
  and that the resource carries the mapped semconv and `atomi.*` attributes.

Both sets of doubles carry no test-framework dependency, so any runner can use them. The
package's own meta tests prove each shipped assertion fails on a known-bad emission and
passes on a known-good one.
