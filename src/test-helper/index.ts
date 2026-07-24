import type { TelemetryAttributes } from '@atomicloud/diene.interfaces';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { checkTraceRecord, type TraceEmitter, type TraceError, type TraceRecord } from '@atomicloud/diene.otel';

interface SequencedCall {
  readonly sequence: number;
}

type TraceCall =
  | (SequencedCall & { readonly method: 'emit'; readonly record: Readonly<TraceRecord> })
  | (SequencedCall & { readonly method: 'flush' });

function cloneTraceRecord(record: Readonly<TraceRecord>): Readonly<TraceRecord> {
  return Object.freeze({
    name: record.name,
    ...(record.attributes === undefined ? {} : { attributes: Object.freeze({ ...record.attributes }) }),
    ...(record.events === undefined
      ? {}
      : {
          events: Object.freeze(
            record.events.map(event =>
              Object.freeze({
                name: event.name,
                ...(event.attributes === undefined ? {} : { attributes: Object.freeze({ ...event.attributes }) }),
              }),
            ),
          ),
        }),
    ...(record.status === undefined ? {} : { status: record.status }),
    ...(record.statusMessage === undefined ? {} : { statusMessage: record.statusMessage }),
  });
}

function comparable(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(comparable);
  if (typeof value === 'object' && value !== null) {
    return Object.fromEntries(
      Object.entries(value)
        .sort(([left], [right]) => (left === right ? 0 : left < right ? -1 : 1))
        .map(([key, entry]) => [key, comparable(entry)]),
    );
  }
  return value;
}

class OtelAssertionError extends Error {
  constructor(
    readonly label: string,
    readonly expected: unknown,
    readonly actual: unknown,
  ) {
    super(
      `${label} mismatch\nExpected: ${JSON.stringify(comparable(expected))}\nActual: ${JSON.stringify(comparable(actual))}`,
    );
    this.name = 'OtelAssertionError';
  }
}

function assertEqual(label: string, actual: unknown, expected: unknown): void {
  if (JSON.stringify(comparable(actual)) !== JSON.stringify(comparable(expected))) {
    throw new OtelAssertionError(label, expected, actual);
  }
}

class InMemoryTraceEmitter implements TraceEmitter {
  private readonly recordedCalls: TraceCall[] = [];
  private readonly recordedRecords: Readonly<TraceRecord>[] = [];
  private nextFailure: TraceError | undefined;
  private sequence = 0;

  get calls(): readonly TraceCall[] {
    return this.recordedCalls.map(call =>
      call.method === 'emit'
        ? Object.freeze({ ...call, record: cloneTraceRecord(call.record) })
        : Object.freeze({ ...call }),
    );
  }

  get records(): readonly Readonly<TraceRecord>[] {
    return this.recordedRecords.map(cloneTraceRecord);
  }

  failNext(error: TraceError): void {
    this.nextFailure = error;
  }

  emit(record: TraceRecord): Result<void, TraceError> {
    const checked = checkTraceRecord(record);
    if (!checked.ok) return Err(checked.error);
    const snapshot = cloneTraceRecord(checked.value);
    this.recordedCalls.push(Object.freeze({ method: 'emit', record: snapshot, sequence: this.sequence++ }));
    const failure = this.nextFailure;
    this.nextFailure = undefined;
    if (failure !== undefined) return Err(failure);
    this.recordedRecords.push(snapshot);
    return Ok(undefined);
  }

  flush(): Result<void, TraceError> {
    this.recordedCalls.push(Object.freeze({ method: 'flush', sequence: this.sequence++ }));
    const failure = this.nextFailure;
    this.nextFailure = undefined;
    return failure === undefined ? Ok(undefined) : Err(failure);
  }
}

function assertTraceRecords(subject: InMemoryTraceEmitter, expected: readonly TraceRecord[]): void {
  assertEqual('Trace records', subject.records, expected);
}

function assertTraceCalls(subject: InMemoryTraceEmitter, expected: readonly TraceCall[]): void {
  assertEqual('Trace calls', subject.calls, expected);
}

function assertResourceAttributes(actual: TelemetryAttributes, expected: TelemetryAttributes): void {
  assertEqual('Resource attributes', actual, expected);
}

function assertTelemetryPayload(actual: unknown, expected: unknown): void {
  assertEqual('Telemetry payload', actual, expected);
}

export type { LoggerCall, MetricsCall } from '@atomicloud/diene.interfaces/test-helper';
export {
  assertLoggerCalls,
  assertLogRecords,
  assertMetricRecords,
  assertMetricsCalls,
  InMemoryLoggerSink,
  InMemoryMetricsCollector,
  InterfaceAssertionError,
} from '@atomicloud/diene.interfaces/test-helper';
export type { TraceCall };
export {
  assertResourceAttributes,
  assertTelemetryPayload,
  assertTraceCalls,
  assertTraceRecords,
  InMemoryTraceEmitter,
  OtelAssertionError,
};
