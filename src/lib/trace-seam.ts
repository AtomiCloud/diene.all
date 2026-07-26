import type { Result } from '@atomicloud/diene.result';

type TraceAttributeValue = boolean | number | string;
type TraceAttributes = Readonly<Record<string, TraceAttributeValue>>;
type TraceStatus = 'error' | 'ok' | 'unset';
type TraceErrorCode = 'invalid-input' | 'io' | 'unavailable' | 'unexpected-call';
type TraceErrorDetails = Readonly<Record<string, unknown>>;

interface TraceEvent {
  readonly name: string;
  readonly attributes?: TraceAttributes;
}

interface TraceRecord {
  readonly name: string;
  readonly attributes?: TraceAttributes;
  readonly events?: readonly TraceEvent[];
  readonly status?: TraceStatus;
  readonly statusMessage?: string;
}

interface TraceEmitter {
  emit(record: TraceRecord): Result<void, TraceError>;
  flush(): Result<void, TraceError>;
}

type TraceCheck<T> = Readonly<{ ok: true; value: T }> | Readonly<{ error: TraceError; ok: false }>;

const TRACE_ERROR_BRAND = Symbol.for('AtomiCloud.Diene.Otel.TraceError');

class TraceError extends Error {
  readonly _tag = 'TraceError' as const;
  readonly details: TraceErrorDetails;

  static override [Symbol.hasInstance](value: unknown): boolean {
    return (
      typeof value === 'object' &&
      value !== null &&
      (value as { readonly [TRACE_ERROR_BRAND]?: unknown })[TRACE_ERROR_BRAND] === true
    );
  }

  constructor(
    readonly code: TraceErrorCode,
    readonly operation: string,
    message: string,
    details: TraceErrorDetails = {},
  ) {
    super(message);
    this.name = 'TraceError';
    this.details = Object.freeze({ ...details });
    Object.defineProperty(this, TRACE_ERROR_BRAND, { value: true });
  }
}

function traceError(
  code: TraceErrorCode,
  operation: string,
  message: string,
  details: TraceErrorDetails = {},
): TraceError {
  return new TraceError(code, operation, message, details);
}

function accepted<T>(value: T): TraceCheck<T> {
  return Object.freeze({ ok: true, value });
}

function rejected<T>(error: TraceError): TraceCheck<T> {
  return Object.freeze({ error, ok: false });
}

function checkTraceAttributes(attributes: unknown, operation = 'emit'): TraceCheck<TraceAttributes | undefined> {
  if (attributes === undefined) return accepted(undefined);
  if (
    typeof attributes !== 'object' ||
    attributes === null ||
    Array.isArray(attributes) ||
    ![Object.prototype, null].includes(Object.getPrototypeOf(attributes))
  ) {
    return rejected(traceError('invalid-input', operation, 'Trace attributes must be a primitive record'));
  }
  const entries = Object.entries(attributes);
  if (entries.some(([key]) => key.trim() === '' || key.includes('\0'))) {
    return rejected(traceError('invalid-input', operation, 'Trace attribute names must be non-blank and NUL-free'));
  }
  const invalidValue = entries.some(([, value]) => {
    const valueType = typeof value;
    return (
      (valueType !== 'boolean' && valueType !== 'number' && valueType !== 'string') ||
      (valueType === 'number' && !Number.isFinite(value))
    );
  });
  if (invalidValue) {
    return rejected(traceError('invalid-input', operation, 'Trace attribute values must be finite primitives'));
  }
  return accepted(
    Object.freeze(
      Object.fromEntries(entries.sort(([left], [right]) => (left === right ? 0 : left < right ? -1 : 1))),
    ) as TraceAttributes,
  );
}

function checkTraceEvent(event: unknown): TraceCheck<Readonly<TraceEvent>> {
  if (typeof event !== 'object' || event === null) {
    return rejected(traceError('invalid-input', 'emit', 'Trace events must be objects'));
  }
  const candidate = event as Partial<TraceEvent>;
  if (typeof candidate.name !== 'string' || candidate.name.trim() === '') {
    return rejected(traceError('invalid-input', 'emit', 'Trace event names must not be blank'));
  }
  const attributes = checkTraceAttributes(candidate.attributes);
  if (!attributes.ok) return attributes;
  return accepted(
    Object.freeze({
      ...(attributes.value === undefined ? {} : { attributes: attributes.value }),
      name: candidate.name,
    }),
  );
}

function checkTraceRecord(record: unknown): TraceCheck<Readonly<TraceRecord>> {
  if (typeof record !== 'object' || record === null) {
    return rejected(traceError('invalid-input', 'emit', 'Trace record must be an object'));
  }
  const candidate = record as Partial<TraceRecord>;
  if (typeof candidate.name !== 'string' || candidate.name.trim() === '') {
    return rejected(traceError('invalid-input', 'emit', 'Trace name must not be blank'));
  }
  if (candidate.status !== undefined && !['error', 'ok', 'unset'].includes(candidate.status)) {
    return rejected(traceError('invalid-input', 'emit', 'Trace status is invalid'));
  }
  if (
    candidate.statusMessage !== undefined &&
    (typeof candidate.statusMessage !== 'string' || candidate.statusMessage.trim() === '')
  ) {
    return rejected(traceError('invalid-input', 'emit', 'Trace status message must not be blank'));
  }
  const attributes = checkTraceAttributes(candidate.attributes);
  if (!attributes.ok) return attributes;
  if (candidate.events !== undefined && !Array.isArray(candidate.events)) {
    return rejected(traceError('invalid-input', 'emit', 'Trace events must be an array'));
  }
  const events: Readonly<TraceEvent>[] = [];
  for (const event of candidate.events ?? []) {
    const checked = checkTraceEvent(event);
    if (!checked.ok) return checked;
    events.push(checked.value);
  }
  return accepted(
    Object.freeze({
      ...(attributes.value === undefined ? {} : { attributes: attributes.value }),
      ...(events.length === 0 ? {} : { events: Object.freeze(events) }),
      name: candidate.name,
      ...(candidate.status === undefined ? {} : { status: candidate.status }),
      ...(candidate.statusMessage === undefined ? {} : { statusMessage: candidate.statusMessage }),
    }),
  );
}

export type {
  TraceAttributes,
  TraceAttributeValue,
  TraceEmitter,
  TraceErrorCode,
  TraceErrorDetails,
  TraceEvent,
  TraceRecord,
  TraceStatus,
};
export { checkTraceAttributes, checkTraceEvent, checkTraceRecord, TraceError, traceError };
