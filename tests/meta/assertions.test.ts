import { describe, it } from 'bun:test';
import type { LogRecord, MetricRecord } from '@atomicloud/diene.interfaces';
import {
  assertLoggerCalls,
  assertLogRecords,
  assertMetricRecords,
  assertMetricsCalls,
  assertResourceAttributes,
  assertTelemetryPayload,
  assertTraceCalls,
  assertTraceRecords,
  InMemoryLoggerSink,
  InMemoryMetricsCollector,
  InMemoryTraceEmitter,
  InterfaceAssertionError,
  type LoggerCall,
  type MetricsCall,
  OtelAssertionError,
  type TraceCall,
} from '@atomicloud/diene.otel/test-helper';
import 'should';
import { expectNoThrow, expectOk, expectThrow } from './support/capture';

// Assert-the-asserter: every shipped helper must pass on a known-good
// interaction and throw a described assertion error on a known-bad one. The
// owned trace/resource/payload asserters raise OtelAssertionError; the
// re-exported interface asserters raise InterfaceAssertionError (parity).

function otelError(fn: () => void): OtelAssertionError {
  const error = expectThrow(fn);
  (error instanceof OtelAssertionError).should.be.true();
  return error as OtelAssertionError;
}

function interfaceError(fn: () => void): InterfaceAssertionError {
  const error = expectThrow(fn);
  (error instanceof InterfaceAssertionError).should.be.true();
  return error as InterfaceAssertionError;
}

async function emitter(): Promise<InMemoryTraceEmitter> {
  const subject = new InMemoryTraceEmitter();
  await expectOk(subject.emit({ name: 'span', attributes: { ok: true } }));
  await expectOk(subject.flush());
  return subject;
}

describe('assertTraceRecords', () => {
  it('should pass on matching records', async () => {
    const subject = await emitter();
    expectNoThrow(() => assertTraceRecords(subject, [{ name: 'span', attributes: { ok: true } }]));
  });

  it('should throw a described OtelAssertionError on a mismatch', async () => {
    const subject = await emitter();
    const error = otelError(() => assertTraceRecords(subject, [{ name: 'other' }]));
    error.label.should.eql('Trace records');
    error.message.should.match(/mismatch/);
  });
});

describe('assertTraceCalls', () => {
  it('should pass on a matching call log', async () => {
    const subject = await emitter();
    const expected: readonly TraceCall[] = [
      { method: 'emit', record: { name: 'span', attributes: { ok: true } }, sequence: 0 },
      { method: 'flush', sequence: 1 },
    ];
    expectNoThrow(() => assertTraceCalls(subject, expected));
  });

  it('should throw on a mismatch', async () => {
    const subject = await emitter();
    const error = otelError(() => assertTraceCalls(subject, [{ method: 'flush', sequence: 0 }]));
    error.label.should.eql('Trace calls');
  });
});

describe('assertResourceAttributes', () => {
  it('should pass on equal attributes regardless of key order', () => {
    // Arrange - unordered keys prove the comparable normalisation
    expectNoThrow(() => assertResourceAttributes({ b: 2, a: 1 }, { a: 1, b: 2 }));
  });

  it('should throw on differing attributes', () => {
    const error = otelError(() => assertResourceAttributes({ a: 1 }, { a: 2 }));
    error.label.should.eql('Resource attributes');
  });
});

describe('assertTelemetryPayload', () => {
  it.each([
    ['a nested object', { a: { b: 1 } }, { a: { b: 1 } }],
    ['an array', [1, 2, 3], [1, 2, 3]],
    ['a null payload', null, null],
  ])('should pass on an equal payload (%s)', (_label, actual, expected) => {
    expectNoThrow(() => assertTelemetryPayload(actual, expected));
  });

  it('should throw on a differing payload', () => {
    const error = otelError(() => assertTelemetryPayload({ a: 1 }, { a: 2 }));
    error.label.should.eql('Telemetry payload');
  });
});

describe('assertLogRecords (re-exported)', () => {
  const arrange = async (): Promise<InMemoryLoggerSink> => {
    const subject = new InMemoryLoggerSink();
    await expectOk(subject.emit({ level: 'info', message: 'hi' }));
    return subject;
  };
  const expected: readonly LogRecord[] = [{ level: 'info', message: 'hi' }];

  it('should pass on matching records', async () => {
    const subject = await arrange();
    expectNoThrow(() => assertLogRecords(subject, expected));
  });

  it('should throw an InterfaceAssertionError on a mismatch', async () => {
    const subject = await arrange();
    const error = interfaceError(() => assertLogRecords(subject, [{ level: 'warn', message: 'hi' }]));
    error.label.should.eql('Log records');
  });
});

describe('assertLoggerCalls (re-exported)', () => {
  const arrange = async (): Promise<InMemoryLoggerSink> => {
    const subject = new InMemoryLoggerSink();
    await expectOk(subject.emit({ level: 'info', message: 'hi' }));
    await expectOk(subject.flush());
    return subject;
  };
  const expected: readonly LoggerCall[] = [
    { method: 'emit', record: { level: 'info', message: 'hi' }, sequence: 0 },
    { method: 'flush', sequence: 1 },
  ];

  it('should pass on a matching call log', async () => {
    const subject = await arrange();
    expectNoThrow(() => assertLoggerCalls(subject, expected));
  });

  it('should throw on a mismatch', async () => {
    const subject = await arrange();
    interfaceError(() => assertLoggerCalls(subject, [{ method: 'flush', sequence: 0 }]));
  });
});

describe('assertMetricRecords (re-exported)', () => {
  const arrange = async (): Promise<InMemoryMetricsCollector> => {
    const subject = new InMemoryMetricsCollector();
    await expectOk(subject.record({ kind: 'counter', name: 'hits', value: 1 }));
    return subject;
  };
  const expected: readonly MetricRecord[] = [{ kind: 'counter', name: 'hits', value: 1 }];

  it('should pass on matching metrics', async () => {
    const subject = await arrange();
    expectNoThrow(() => assertMetricRecords(subject, expected));
  });

  it('should throw on a mismatch', async () => {
    const subject = await arrange();
    interfaceError(() => assertMetricRecords(subject, [{ kind: 'gauge', name: 'hits', value: 1 }]));
  });
});

describe('assertMetricsCalls (re-exported)', () => {
  const arrange = async (): Promise<InMemoryMetricsCollector> => {
    const subject = new InMemoryMetricsCollector();
    await expectOk(subject.record({ kind: 'counter', name: 'hits', value: 1 }));
    await expectOk(subject.flush());
    return subject;
  };
  const expected: readonly MetricsCall[] = [
    { method: 'record', metric: { kind: 'counter', name: 'hits', value: 1 }, sequence: 0 },
    { method: 'flush', sequence: 1 },
  ];

  it('should pass on a matching call log', async () => {
    const subject = await arrange();
    expectNoThrow(() => assertMetricsCalls(subject, expected));
  });

  it('should throw on a mismatch', async () => {
    const subject = await arrange();
    interfaceError(() => assertMetricsCalls(subject, [{ method: 'flush', sequence: 0 }]));
  });
});
