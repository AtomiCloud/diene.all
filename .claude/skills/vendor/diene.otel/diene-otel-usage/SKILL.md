---
name: diene-otel-usage
description: Use when consuming @atomicloud/diene.otel — composing the OTel config block into a service schema, initializing signals and flushing on shutdown, or testing telemetry with the test-helper trace double and the interfaces logger/metrics mocks.
---

`@atomicloud/diene.otel` wires OpenTelemetry for the AtomiCloud Bun family and ships
as dual **ESM + CJS** with bundled types. It owns the **engine-owned config block
schema**, the **canonical resource identity**, the **signal lifecycle**
(init / flush / shutdown), the **pino logs bridge**, and the **language-local trace
seam**. It ships no config loader and picks no landscape endpoints.

- **Schema and types** import from the package root.
- **Telemetry test doubles** import from `@atomicloud/diene.otel/test-helper`.

## The canonical block

Signal keys are exactly `logs`, `metrics`, and `traces`. Exporter selection is
independent per-exporter `enabled` booleans (no enum strings). OTLP is HTTP/protobuf
on port 4318. Durations are ISO-8601 strings (`PT10S`, `PT60S`). The base block turns
the pipelines on but keeps exporters **off**; a landscape overlay flips the exporter it
needs on and supplies the endpoint. See
[the otel standard](../../docs/standards/otel/index.md) for the frozen block and its
invariants.

## Compose the schema in one line

The service imports this block schema into its composed root schema; `standard-config`
never wraps it and `lib/bun/config` is the sole merger and final validator:

```ts
import { otelBlockSchema } from '@atomicloud/diene.otel';
import { z } from 'zod';

const rootSchema = z.object({
  app: appSchema,
  otel: otelBlockSchema,
  // ...the rest of the service config
});
```

## Init and flush (the consumer owns SIGTERM)

Initialize the enabled pipelines once from the validated block and the `app:` values,
use the accessors, and call the returned flush / shutdown yourself on shutdown. The
library registers **no** process signal handlers.

```ts
import { initOtel } from '@atomicloud/diene.otel';

const telemetry = initOtel(config.otel, {
  landscape: config.app.landscape,
  module: config.app.module,
  platform: config.app.platform,
  service: config.app.service,
  version: buildVersion,
});

telemetry.logger.info('service started');
await telemetry.metricsCollector.record({ kind: 'counter', name: 'service.starts', value: 1 }).unwrap();

// The consumer lifecycle owns this call (for example, from its SIGTERM handler).
await telemetry.shutdown();
```

- Standard `OTEL_*` environment variables win over the block; the library only sets an
  option the operator has not set. `OTEL_SDK_DISABLED` makes init a whole no-op.
- A disabled signal or exporter constructs no exporter, reader, timer, or network client.
- Logs go through pino (JSON stdout → Alloy) with trace-context injection; the OTLP logs
  bridge is a documented stub in v1.

## Testing telemetry

- **Logging and metrics doubles come from the interfaces package**, not this one:
  `InMemoryLoggerSink`, `InMemoryMetricsCollector`, and their assertions live at
  `@atomicloud/diene.interfaces/test-helper`. Inject them where init expects a
  `LoggerSink` / `MetricsCollector`.
- **Trace doubles and OTel-specific asserters live here** (RB-19): import
  `InMemoryTraceEmitter` and the resource / span asserters from
  `@atomicloud/diene.otel/test-helper`.
- Injected seams are selected before signal construction, so their corresponding real SDK
  providers/exporters (and active pino output) are not built even when OTLP is enabled.
- Integration tests use these in-memory seams and **never start a collector or open a
  network client**. Real `:4318` export is a consumer-owned SIT journey.

```ts
import { InMemoryLoggerSink, InMemoryMetricsCollector } from '@atomicloud/diene.interfaces/test-helper';
import { assertResourceAttributes, assertTraceRecords, InMemoryTraceEmitter } from '@atomicloud/diene.otel/test-helper';

const logger = new InMemoryLoggerSink();
const metrics = new InMemoryMetricsCollector();
const traces = new InMemoryTraceEmitter();
const telemetry = initOtel(config.otel, appIdentity, {
  seams: { logger, metrics, traces },
});

await telemetry.traceEmitter.emit({ name: 'example.operation', status: 'ok' }).unwrap();
assertTraceRecords(traces, [{ name: 'example.operation', status: 'ok' }]);
assertResourceAttributes(telemetry.resourceAttributes, expectedResourceAttributes);
await telemetry.shutdown();
```

Read [patterns.md](patterns.md) for the do's, don'ts, wiring, and the test-double split.
Read the otel standard for resource mapping, sampler mapping, the `OTEL_*` precedence
rules, the logs stance, and the trace-seam ownership boundary.
