import { describe, it } from 'bun:test';
// The int tier dogfoods the SHIPPED mocks and assertion helpers from
// @atomicloud/diene.otel/test-helper (which re-exports the registry logging and
// metrics mocks). bunfig.int.toml excludes src/test-helper/** so the meta code
// never enters the adapters coverage ledger.
import {
  assertLogRecords,
  assertMetricRecords,
  assertResourceAttributes,
  assertTraceRecords,
  InMemoryLoggerSink,
  InMemoryMetricsCollector,
  InMemoryTraceEmitter,
} from '@atomicloud/diene.otel/test-helper';
import 'should';
import { initOtel, selectedExporters } from '../../src/adapters/init';
import type { AppIdentity } from '../../src/lib/resource';
import { defaultOtelBlock, type OtelBlock } from '../../src/lib/schema';
import { makeCaptureStream, makeTracer } from './support/doubles';
import { makeFailingFlushTraceEmitter, makeMetricFactories, makeTraceFactories } from './support/factories';
import { expectOk } from './support/result';

const identity: AppIdentity = {
  landscape: 'lapras',
  platform: 'atomi',
  service: 'diene',
  module: 'otel',
  version: '1.0.0',
};

function baseBlock(): OtelBlock {
  return { ...defaultOtelBlock };
}

function tracesActiveBlock(): OtelBlock {
  return {
    ...defaultOtelBlock,
    traces: {
      ...defaultOtelBlock.traces,
      exporter: { ...defaultOtelBlock.traces.exporter, console: { enabled: true } },
    },
  };
}

// Every signal ships an enabled OTLP exporter with a valid endpoint. Injecting
// seams over this block proves the SDK pipeline is never built for a signal an
// injected double owns, even when its exporter would otherwise be selected.
function otlpEnabledBlock(): OtelBlock {
  const otlp = {
    enabled: true,
    endpoint: 'http://otel-collector:4318',
    protocol: 'http/protobuf' as const,
    headers: {},
    timeout: 'PT10S',
  };
  return {
    ...defaultOtelBlock,
    logs: { ...defaultOtelBlock.logs, exporter: { ...defaultOtelBlock.logs.exporter, otlp } },
    metrics: { ...defaultOtelBlock.metrics, exporter: { ...defaultOtelBlock.metrics.exporter, otlp } },
    traces: { ...defaultOtelBlock.traces, exporter: { ...defaultOtelBlock.traces.exporter, otlp } },
  };
}

function injected() {
  return {
    trace: makeTraceFactories(makeTracer().tracer),
    metric: makeMetricFactories(),
  };
}

describe('selectedExporters', () => {
  it('should force every signal to no exporters when the SDK is disabled', () => {
    // Act
    const actual = selectedExporters(true, defaultOtelBlock, {});

    // Assert
    actual.logs.should.eql({ console: false, otlp: false });
    actual.metrics.should.eql({ console: false, otlp: false });
    actual.traces.should.eql({ console: false, otlp: false });
  });

  it('should resolve per-signal selections from the block when enabled', () => {
    // Arrange - traces console enabled in the block
    const block: OtelBlock = {
      ...defaultOtelBlock,
      traces: {
        ...defaultOtelBlock.traces,
        exporter: { ...defaultOtelBlock.traces.exporter, console: { enabled: true } },
      },
    };

    // Act
    const actual = selectedExporters(false, block, {});

    // Assert
    actual.traces.should.eql({ console: true, otlp: false });
    actual.logs.should.eql({ console: false, otlp: false });
  });
});

describe('initOtel', () => {
  it('should construct no exporters and report inactive signals when every exporter is off (G1)', async () => {
    // Arrange
    const { trace, metric } = injected();

    // Act - the canonical block: signals enabled, all exporters off
    const runtime = initOtel(baseBlock(), identity, {
      environment: {},
      traceSignalFactories: trace.factories,
      metricExporterFactories: metric.factories,
    });

    // Assert - nothing built a client, reader, processor or provider
    runtime.active.should.eql({ logs: false, metrics: false, traces: false });
    trace.consoleCalls.should.eql(0);
    trace.otlpCalls.should.eql(0);
    trace.processorCalls.should.eql(0);
    trace.providerCalls.should.eql(0);
    trace.registerCalls.should.eql(0);
    metric.consoleCalls.should.eql(0);
    metric.otlpCalls.should.eql(0);
    runtime.resourceAttributes.should.containEql({ 'service.name': 'diene', 'atomi.module': 'otel' });
    runtime.otlpLogsBridge.should.eql('stubbed');

    // Cleanup
    await runtime.shutdown();
  });

  it('should adopt injected seams and route payloads through them', async () => {
    // Arrange - the shipped in-memory seams capture what the runtime emits
    const { trace, metric } = injected();
    const logger = new InMemoryLoggerSink();
    const metrics = new InMemoryMetricsCollector();
    const traces = new InMemoryTraceEmitter();

    // Act
    const runtime = initOtel(baseBlock(), identity, {
      environment: {},
      seams: { logger, metrics, traces },
      traceSignalFactories: trace.factories,
      metricExporterFactories: metric.factories,
    });

    // Assert - the runtime exposes the injected seams, not the SDK-backed ones
    (runtime.loggerSink === logger).should.be.true();
    (runtime.metricsCollector === metrics).should.be.true();
    (runtime.traceEmitter === traces).should.be.true();

    // Act - emit one payload per signal through the runtime seams
    await expectOk(runtime.loggerSink.emit({ level: 'info', message: 'ready' }));
    await expectOk(runtime.metricsCollector.record({ kind: 'counter', name: 'starts', value: 1 }));
    await expectOk(runtime.traceEmitter.emit({ name: 'boot' }));

    // Assert - captured by the mocks and cross-checked with the shipped helpers
    assertLogRecords(logger, [{ level: 'info', message: 'ready' }]);
    assertMetricRecords(metrics, [{ kind: 'counter', name: 'starts', value: 1 }]);
    assertTraceRecords(traces, [{ name: 'boot' }]);

    // Assert - the mapped resource attributes match the fixed R14 mapping
    assertResourceAttributes(runtime.resourceAttributes, {
      'deployment.environment.name': 'lapras',
      'service.namespace': 'atomi',
      'service.name': 'diene',
      'service.version': '1.0.0',
      'atomi.landscape': 'lapras',
      'atomi.module': 'otel',
      'atomi.platform': 'atomi',
      'atomi.service': 'diene',
      'atomi.version': '1.0.0',
    });

    // Cleanup
    await runtime.shutdown();
  });

  it('should select injected seams before SDK construction even with OTLP enabled', async () => {
    // Arrange - every signal ships an enabled OTLP exporter, yet all three seams
    // are injected. The reconciliation must happen before any SDK construction.
    const { trace, metric } = injected();
    const logger = new InMemoryLoggerSink();
    const metrics = new InMemoryMetricsCollector();
    const traces = new InMemoryTraceEmitter();
    const capture = makeCaptureStream();

    // Act
    const runtime = initOtel(otlpEnabledBlock(), identity, {
      environment: {},
      destination: capture,
      seams: { logger, metrics, traces },
      traceSignalFactories: trace.factories,
      metricExporterFactories: metric.factories,
    });

    // Assert - no exporter, reader, processor, provider or registration was built
    trace.consoleCalls.should.eql(0);
    trace.otlpCalls.should.eql(0);
    trace.processorCalls.should.eql(0);
    trace.providerCalls.should.eql(0);
    trace.registerCalls.should.eql(0);
    metric.consoleCalls.should.eql(0);
    metric.otlpCalls.should.eql(0);
    runtime.active.should.eql({ logs: false, metrics: false, traces: false });

    // Assert - the runtime exposes the injected seams, not SDK-backed ones
    (runtime.loggerSink === logger).should.be.true();
    (runtime.metricsCollector === metrics).should.be.true();
    (runtime.traceEmitter === traces).should.be.true();

    // Act - emissions still reach the injected seams
    await expectOk(runtime.loggerSink.emit({ level: 'info', message: 'ready' }));
    await expectOk(runtime.metricsCollector.record({ kind: 'counter', name: 'starts', value: 1 }));
    await expectOk(runtime.traceEmitter.emit({ name: 'boot' }));

    // Assert - captured by the mocks; no active pino output reached the stream
    assertLogRecords(logger, [{ level: 'info', message: 'ready' }]);
    assertMetricRecords(metrics, [{ kind: 'counter', name: 'starts', value: 1 }]);
    assertTraceRecords(traces, [{ name: 'boot' }]);
    capture.lines.should.eql([]);

    // Cleanup
    await runtime.shutdown();
  });

  it('should ignore seams and stay inactive when OTEL_SDK_DISABLED is set', async () => {
    // Arrange
    const { trace, metric } = injected();
    const logger = new InMemoryLoggerSink();
    const traces = new InMemoryTraceEmitter();

    // Act
    const runtime = initOtel(baseBlock(), identity, {
      environment: { OTEL_SDK_DISABLED: 'true' },
      seams: { logger, traces },
      traceSignalFactories: trace.factories,
      metricExporterFactories: metric.factories,
    });

    // Assert - disabled init falls back to the (no-op) signal seams
    runtime.active.should.eql({ logs: false, metrics: false, traces: false });
    (runtime.loggerSink === logger).should.be.false();
    (runtime.traceEmitter === traces).should.be.false();

    // Cleanup
    await runtime.shutdown();
  });

  it('should no-op flush after shutdown', async () => {
    // Arrange - the shipped mock records every flush call it receives
    const { trace, metric } = injected();
    const traces = new InMemoryTraceEmitter();
    const runtime = initOtel(baseBlock(), identity, {
      environment: {},
      seams: { logger: new InMemoryLoggerSink(), metrics: new InMemoryMetricsCollector(), traces },
      traceSignalFactories: trace.factories,
      metricExporterFactories: metric.factories,
    });
    const flushes = (): number => traces.calls.filter(call => call.method === 'flush').length;

    // Act
    await runtime.flush();
    await runtime.shutdown();
    const flushesBeforeReflush = flushes();
    await runtime.flush();

    // Assert - the post-shutdown flush is a no-op
    flushes().should.eql(flushesBeforeReflush);
  });

  it('should shut down providers exactly once across repeated calls', async () => {
    // Arrange - an active trace exporter builds a real (faked) provider to shut down
    const { trace, metric } = injected();
    const runtime = initOtel(tracesActiveBlock(), identity, {
      environment: {},
      traceSignalFactories: trace.factories,
      metricExporterFactories: metric.factories,
    });

    // Act
    await Promise.all([runtime.shutdown(), runtime.shutdown()]);

    // Assert
    trace.provider.shutdownCalls.should.eql(1);
  });

  it('should aggregate flush and shutdown failures into an AggregateError', async () => {
    // Arrange - an injected trace seam whose flush errors. The seam owns the
    // signal, so no SDK provider is built; the flush failure alone must surface.
    const trace = makeTraceFactories(makeTracer().tracer, { shutdown: true });
    const metric = makeMetricFactories();
    const runtime = initOtel(baseBlock(), identity, {
      environment: {},
      seams: {
        logger: new InMemoryLoggerSink(),
        metrics: new InMemoryMetricsCollector(),
        traces: makeFailingFlushTraceEmitter(),
      },
      traceSignalFactories: trace.factories,
      metricExporterFactories: metric.factories,
    });

    // Act
    let caught: unknown;
    try {
      await runtime.shutdown();
    } catch (error) {
      caught = error;
    }

    // Assert
    (caught instanceof AggregateError).should.be.true();
  });

  it('should aggregate an active provider shutdown rejection', async () => {
    // Arrange - an active trace pipeline whose provider rejects shutdown
    const trace = makeTraceFactories(makeTracer().tracer, { shutdown: true });
    const metric = makeMetricFactories();
    const runtime = initOtel(tracesActiveBlock(), identity, {
      environment: {},
      traceSignalFactories: trace.factories,
      metricExporterFactories: metric.factories,
    });

    // Act
    let caught: unknown;
    try {
      await runtime.shutdown();
    } catch (error) {
      caught = error;
    }

    // Assert - the allSettled rejection is retained in the aggregate
    (caught instanceof AggregateError).should.be.true();
  });

  it('should tolerate a missing metrics provider on shutdown', async () => {
    // Arrange - metrics disabled means createMetricSignal builds no provider
    const { trace, metric } = injected();
    const block: OtelBlock = { ...defaultOtelBlock, metrics: { ...defaultOtelBlock.metrics, enabled: false } };
    const runtime = initOtel(block, identity, {
      environment: {},
      traceSignalFactories: trace.factories,
      metricExporterFactories: metric.factories,
    });

    // Act / Assert
    runtime.active.metrics.should.be.false();
    await runtime.shutdown();
  });

  it('should default the environment to process.env and use real providers', async () => {
    // Arrange - isolate the OTEL_* keys init reads so the run is deterministic
    const keys = [
      'OTEL_SDK_DISABLED',
      'OTEL_LOGS_EXPORTER',
      'OTEL_METRICS_EXPORTER',
      'OTEL_TRACES_EXPORTER',
      'OTEL_TRACES_SAMPLER',
    ];
    const saved = new Map(keys.map(key => [key, process.env[key]]));
    for (const key of keys) delete process.env[key];
    const capture = makeCaptureStream();

    try {
      // Act - no options.environment and no injected factories: real SDK, exporters off
      const runtime = initOtel(baseBlock(), identity, { destination: capture });

      // Assert - exporters off means no active signal and no leaked timers
      runtime.active.should.eql({ logs: false, metrics: false, traces: false });

      // Cleanup
      await runtime.shutdown();
    } finally {
      for (const [key, value] of saved) if (value !== undefined) process.env[key] = value;
    }
  });
});
