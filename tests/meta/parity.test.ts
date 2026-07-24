import { describe } from 'bun:test';
import type { LogRecord, MetricRecord } from '@atomicloud/diene.interfaces';
import { InMemoryLoggerSink, InMemoryMetricsCollector, InMemoryTraceEmitter } from '@atomicloud/diene.otel/test-helper';
import type { Tracer } from '@opentelemetry/api';
import { MeterProvider } from '@opentelemetry/sdk-metrics';
import { createLoggerSignal } from '../../src/adapters/signals/logs';
import { SdkMetricsCollector } from '../../src/adapters/signals/metrics';
import { SdkTraceEmitter } from '../../src/adapters/signals/traces';
import type { SeamContract } from './contract/behaviours';
import { runSeamContract } from './contract/behaviours';

function captureStream(): { write(chunk: string): void } {
  const lines: string[] = [];
  return { write: (chunk: string) => void lines.push(chunk) };
}

function fakeTracer(): Tracer {
  const span = {
    addEvent: () => span,
    setStatus: () => span,
    end: () => undefined,
  };
  return { startSpan: () => span } as unknown as Tracer;
}

const invalidLog = { level: 'nope', message: 'hi' } as unknown as LogRecord;
const invalidMetric: MetricRecord = { kind: 'counter', name: '', value: 1 };

describe('LoggerSink contract parity', () => {
  describe('PinoLoggerSink (real adapter)', () => {
    runSeamContract((): SeamContract => {
      const sink = createLoggerSignal(true, { console: true, otlp: false }, {}, captureStream()).sink;
      return {
        validOperation: () => sink.emit({ level: 'info', message: 'hi' }),
        invalidOperation: () => sink.emit(invalidLog),
        flush: () => sink.flush(),
      };
    });
  });

  describe('InMemoryLoggerSink (mock)', () => {
    runSeamContract((): SeamContract => {
      const sink = new InMemoryLoggerSink();
      return {
        validOperation: () => sink.emit({ level: 'info', message: 'hi' }),
        invalidOperation: () => sink.emit(invalidLog),
        flush: () => sink.flush(),
      };
    });
  });
});

describe('MetricsCollector contract parity', () => {
  describe('SdkMetricsCollector (real adapter)', () => {
    runSeamContract((): SeamContract => {
      // A reader-less MeterProvider gives a real meter with no background timer.
      const collector = new SdkMetricsCollector(new MeterProvider().getMeter('parity'));
      return {
        validOperation: () => collector.record({ kind: 'counter', name: 'hits', value: 1 }),
        invalidOperation: () => collector.record(invalidMetric),
        flush: () => collector.flush(),
      };
    });
  });

  describe('InMemoryMetricsCollector (mock)', () => {
    runSeamContract((): SeamContract => {
      const collector = new InMemoryMetricsCollector();
      return {
        validOperation: () => collector.record({ kind: 'counter', name: 'hits', value: 1 }),
        invalidOperation: () => collector.record(invalidMetric),
        flush: () => collector.flush(),
      };
    });
  });
});

describe('TraceEmitter contract parity', () => {
  describe('SdkTraceEmitter (real adapter)', () => {
    runSeamContract((): SeamContract => {
      const emitter = new SdkTraceEmitter(fakeTracer());
      return {
        validOperation: () => emitter.emit({ name: 'span' }),
        invalidOperation: () => emitter.emit({ name: '' }),
        flush: () => emitter.flush(),
      };
    });
  });

  describe('InMemoryTraceEmitter (mock)', () => {
    runSeamContract((): SeamContract => {
      const emitter = new InMemoryTraceEmitter();
      return {
        validOperation: () => emitter.emit({ name: 'span' }),
        invalidOperation: () => emitter.emit({ name: '' }),
        flush: () => emitter.flush(),
      };
    });
  });
});
