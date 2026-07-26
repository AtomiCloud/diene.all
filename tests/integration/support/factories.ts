import { Err, Ok } from '@atomicloud/diene.result';
import type { Meter, Tracer } from '@opentelemetry/api';
import { ExportResultCode } from '@opentelemetry/core';
import type { PushMetricExporter, ResourceMetrics } from '@opentelemetry/sdk-metrics';
import type { MetricExporterFactories } from '../../../src/adapters/signals/metrics';
import type { TraceProvider, TraceSignalFactories } from '../../../src/adapters/signals/traces';
import type { TraceEmitter } from '../../../src/lib/trace-seam';
import { traceError } from '../../../src/lib/trace-seam';

// Injected factory doubles keep every provider/exporter in-process. Trace
// providers are fully faked (no NodeTracerProvider, no BatchSpanProcessor
// timer); metric exporters capture pushed batches so the real MeterProvider +
// PeriodicExportingMetricReader path can be exercised and then shut down
// without a collector.

class FakeTraceProvider implements TraceProvider {
  registered = false;
  forceFlushCalls = 0;
  shutdownCalls = 0;

  constructor(
    private readonly tracer: Tracer,
    private readonly rejections: { readonly flush?: boolean; readonly shutdown?: boolean } = {},
  ) {}

  getTracer(): Tracer {
    return this.tracer;
  }

  async forceFlush(): Promise<void> {
    this.forceFlushCalls += 1;
    if (this.rejections.flush) throw new Error('trace flush failed');
  }

  async shutdown(): Promise<void> {
    this.shutdownCalls += 1;
    if (this.rejections.shutdown) throw new Error('trace shutdown failed');
  }

  register(): void {
    this.registered = true;
  }
}

interface TraceFactorySpy {
  readonly factories: TraceSignalFactories;
  readonly provider: FakeTraceProvider;
  consoleCalls: number;
  otlpCalls: number;
  processorCalls: number;
  providerCalls: number;
  registerCalls: number;
}

function makeTraceFactories(
  tracer: Tracer,
  rejections: { readonly flush?: boolean; readonly shutdown?: boolean } = {},
): TraceFactorySpy {
  const provider = new FakeTraceProvider(tracer, rejections);
  const spy: TraceFactorySpy = {
    provider,
    consoleCalls: 0,
    otlpCalls: 0,
    processorCalls: 0,
    providerCalls: 0,
    registerCalls: 0,
    factories: {
      console: () => {
        spy.consoleCalls += 1;
        return { export: () => undefined, shutdown: async () => undefined } as unknown as ReturnType<
          TraceSignalFactories['console']
        >;
      },
      otlp: () => {
        spy.otlpCalls += 1;
        return { export: () => undefined, shutdown: async () => undefined } as unknown as ReturnType<
          TraceSignalFactories['otlp']
        >;
      },
      processor: exporter => {
        spy.processorCalls += 1;
        return {
          onStart: () => undefined,
          onEnd: () => undefined,
          forceFlush: async () => undefined,
          shutdown: async () => undefined,
          exporter,
        } as unknown as ReturnType<TraceSignalFactories['processor']>;
      },
      provider: () => {
        spy.providerCalls += 1;
        return provider;
      },
      register: target => {
        spy.registerCalls += 1;
        target.register?.();
      },
    },
  };
  return spy;
}

class CapturingMetricExporter implements PushMetricExporter {
  readonly exported: ResourceMetrics[] = [];

  export(metrics: ResourceMetrics, resultCallback: (result: { code: number }) => void): void {
    this.exported.push(metrics);
    resultCallback({ code: ExportResultCode.SUCCESS });
  }

  async forceFlush(): Promise<void> {
    return undefined;
  }

  async shutdown(): Promise<void> {
    return undefined;
  }
}

interface MetricFactorySpy {
  readonly factories: MetricExporterFactories;
  readonly exporter: CapturingMetricExporter;
  consoleCalls: number;
  otlpCalls: number;
}

function makeMetricFactories(): MetricFactorySpy {
  const exporter = new CapturingMetricExporter();
  const spy: MetricFactorySpy = {
    exporter,
    consoleCalls: 0,
    otlpCalls: 0,
    factories: {
      console: () => {
        spy.consoleCalls += 1;
        return exporter;
      },
      otlp: () => {
        spy.otlpCalls += 1;
        return exporter;
      },
    },
  };
  return spy;
}

function makeThrowingMeter(): Meter {
  return {
    createCounter() {
      throw new Error('instrument creation failed');
    },
    createGauge() {
      throw new Error('instrument creation failed');
    },
    createHistogram() {
      throw new Error('instrument creation failed');
    },
  } as unknown as Meter;
}

function makeFailingFlushTraceEmitter(): TraceEmitter {
  return {
    emit: () => Ok(undefined),
    flush: () => Err(traceError('io', 'flush', 'trace flush failed')),
  };
}

export type { MetricFactorySpy, TraceFactorySpy };
export {
  CapturingMetricExporter,
  FakeTraceProvider,
  makeFailingFlushTraceEmitter,
  makeMetricFactories,
  makeThrowingMeter,
  makeTraceFactories,
};
