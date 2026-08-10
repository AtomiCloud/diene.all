import { describe, it } from 'bun:test';
import 'should';
import type { TraceAttributes, TraceEvent, TraceRecord } from '../../src/lib/trace-seam';
import {
  checkTraceAttributes,
  checkTraceEvent,
  checkTraceRecord,
  TraceError,
  traceError,
} from '../../src/lib/trace-seam';

// The trace seam is language-local (RB-19): interfaces ships no trace port, so
// this lib owns the TraceEmitter shape, its TraceError, and the shared
// check* validators. These tests pin the validator contract the in-memory mock
// and the SDK-backed emitter both run before touching a span.

type Checked<T> = Readonly<{ ok: true; value: T }> | Readonly<{ ok: false; error: TraceError }>;

function expectAccepted<T>(checked: Checked<T>): T {
  checked.ok.should.be.true();
  if (!checked.ok) throw new Error('expected an accepted check');
  return checked.value;
}

function expectRejected<T>(checked: Checked<T>): TraceError {
  checked.ok.should.be.false();
  if (checked.ok) throw new Error('expected a rejected check');
  return checked.error;
}

describe('traceError', () => {
  it('should build a tagged, frozen-detail TraceError', () => {
    // Act
    const actual = traceError('io', 'flush', 'boom', { attempt: 2 });

    // Assert
    actual.code.should.eql('io');
    actual.operation.should.eql('flush');
    actual.message.should.eql('boom');
    actual._tag.should.eql('TraceError');
    actual.name.should.eql('TraceError');
    actual.details.should.eql({ attempt: 2 });
    Object.isFrozen(actual.details).should.be.true();
  });

  it('should default the details to an empty frozen record', () => {
    // Act
    const actual = traceError('unexpected-call', 'emit', 'no impl');

    // Assert
    actual.details.should.eql({});
  });
});

describe('TraceError instanceof', () => {
  it('should recognise a constructed TraceError', () => {
    // Arrange
    const error = traceError('invalid-input', 'emit', 'bad');

    // Assert - brand-based hasInstance
    (error instanceof TraceError).should.be.true();
  });

  it.each([
    ['a plain object', {} as unknown],
    ['null', null as unknown],
    ['a primitive', 5 as unknown],
  ])('should reject %s', (_label, value) => {
    // Assert
    (value instanceof TraceError).should.be.false();
  });
});

describe('checkTraceAttributes', () => {
  it('should accept undefined attributes as undefined', () => {
    // Act
    const actual = expectAccepted(checkTraceAttributes(undefined));

    // Assert
    (actual === undefined).should.be.true();
  });

  it('should sort and freeze a primitive record', () => {
    // Arrange - unsorted keys and every primitive value kind
    const input = { zebra: 'z', alpha: 1, mid: true } as TraceAttributes;

    // Act
    const actual = expectAccepted(checkTraceAttributes(input));

    // Assert
    Object.keys(actual ?? {}).should.eql(['alpha', 'mid', 'zebra']);
    Object.isFrozen(actual).should.be.true();
  });

  it('should accept a null-prototype record', () => {
    // Arrange
    const input = Object.assign(Object.create(null), { a: 1 }) as TraceAttributes;

    // Act
    const actual = expectAccepted(checkTraceAttributes(input));

    // Assert
    (actual === undefined).should.be.false();
    if (actual !== undefined) actual.should.eql({ a: 1 });
  });

  it.each([
    ['a primitive', 5 as unknown],
    ['null', null as unknown],
    ['an array', [] as unknown],
    ['a Map', new Map() as unknown],
    ['a class instance', new (class Attrs {})() as unknown],
  ])('should reject non-record attributes (%s)', (_label, value) => {
    // Act
    const error = expectRejected(checkTraceAttributes(value as TraceAttributes));

    // Assert
    error.code.should.eql('invalid-input');
    error.message.should.match(/primitive record/);
  });

  it.each([
    ['a blank name', '   '],
    ['a NUL in the name', 'a\0b'],
  ])('should reject %s', (_label, key) => {
    // Act
    const error = expectRejected(checkTraceAttributes({ [key]: 1 } as TraceAttributes));

    // Assert
    error.message.should.match(/non-blank and NUL-free/);
  });

  it.each([
    ['a nested object value', { a: {} as unknown as number }],
    ['a NaN value', { a: Number.NaN }],
    ['an Infinity value', { a: Number.POSITIVE_INFINITY }],
  ])('should reject %s', (_label, input) => {
    // Act
    const error = expectRejected(checkTraceAttributes(input as TraceAttributes));

    // Assert
    error.message.should.match(/finite primitives/);
  });

  it('should carry the supplied operation onto the rejection', () => {
    // Act
    const error = expectRejected(checkTraceAttributes(5 as unknown as TraceAttributes, 'record'));

    // Assert
    error.operation.should.eql('record');
  });
});

describe('checkTraceEvent', () => {
  it('should accept an event with attributes', () => {
    // Act
    const actual = expectAccepted(checkTraceEvent({ name: 'cache.hit', attributes: { key: 'k' } }));

    // Assert
    actual.name.should.eql('cache.hit');
    (actual.attributes === undefined).should.be.false();
    if (actual.attributes !== undefined) actual.attributes.should.eql({ key: 'k' });
  });

  it('should accept an event without attributes', () => {
    // Act
    const actual = expectAccepted(checkTraceEvent({ name: 'started' }));

    // Assert
    actual.name.should.eql('started');
    (actual.attributes === undefined).should.be.true();
  });

  it.each([
    ['a non-object', null as unknown],
    ['a blank name', { name: '  ' } as unknown],
  ])('should reject %s', (_label, value) => {
    // Act
    const error = expectRejected(checkTraceEvent(value));

    // Assert
    error.code.should.eql('invalid-input');
  });

  it('should propagate an attribute rejection', () => {
    // Act
    const error = expectRejected(checkTraceEvent({ name: 'e', attributes: 5 as unknown }));

    // Assert
    error.message.should.match(/primitive record/);
  });
});

describe('checkTraceRecord', () => {
  it('should accept a fully populated record', () => {
    // Arrange
    const input: TraceRecord = {
      name: 'http.request',
      attributes: { 'http.method': 'GET' },
      events: [{ name: 'sent', attributes: { bytes: 12 } }],
      status: 'ok',
      statusMessage: 'done',
    };

    // Act
    const actual = expectAccepted(checkTraceRecord(input));

    // Assert
    actual.name.should.eql('http.request');
    actual.status?.should.eql('ok');
    actual.statusMessage?.should.eql('done');
    (actual.events ?? []).length.should.eql(1);
  });

  it('should accept a minimal name-only record without optional keys', () => {
    // Act
    const actual = expectAccepted(checkTraceRecord({ name: 'span' }));

    // Assert
    actual.name.should.eql('span');
    (actual.attributes === undefined).should.be.true();
    (actual.events === undefined).should.be.true();
    (actual.status === undefined).should.be.true();
    (actual.statusMessage === undefined).should.be.true();
  });

  it('should drop an empty events array to no events key', () => {
    // Act
    const actual = expectAccepted(checkTraceRecord({ name: 'span', events: [] }));

    // Assert
    (actual.events === undefined).should.be.true();
  });

  it.each([
    ['a non-object', null as unknown],
    ['a blank name', { name: ' ' } as unknown],
    ['an invalid status', { name: 's', status: 'bad' } as unknown],
    ['a non-string status message', { name: 's', statusMessage: 5 } as unknown],
    ['a blank status message', { name: 's', statusMessage: '  ' } as unknown],
    ['non-array events', { name: 's', events: 'nope' } as unknown],
  ])('should reject %s', (_label, value) => {
    // Act
    const error = expectRejected(checkTraceRecord(value));

    // Assert
    error.code.should.eql('invalid-input');
  });

  it('should propagate an attribute rejection', () => {
    // Act
    const error = expectRejected(checkTraceRecord({ name: 's', attributes: 5 as unknown }));

    // Assert
    error.message.should.match(/primitive record/);
  });

  it('should propagate an event rejection', () => {
    // Arrange
    const input = { name: 's', events: [{ name: '' } as TraceEvent] };

    // Act
    const error = expectRejected(checkTraceRecord(input));

    // Assert
    error.message.should.match(/blank/);
  });

  it('should accept a record whose status is present without a message', () => {
    // Act
    const actual = expectAccepted(checkTraceRecord({ name: 's', status: 'unset' }));

    // Assert
    actual.status?.should.eql('unset');
    (actual.statusMessage === undefined).should.be.true();
  });
});
