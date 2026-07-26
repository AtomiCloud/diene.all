import { describe, it } from 'bun:test';
import type { LogRecord } from '@atomicloud/diene.interfaces';
import type { SpanContext } from '@opentelemetry/api';
import 'should';
import {
  activeSpanContext,
  createLoggerSignal,
  OTLP_LOGS_BRIDGE_STATUS,
  PinoLoggerSink,
  traceContextFields,
} from '../../src/adapters/signals/logs';
import { makeCaptureStream, makeLogger, VALID_SPAN_CONTEXT } from './support/doubles';
import { expectErr, expectOk } from './support/result';

const resource = { 'service.name': 'diene', 'atomi.module': 'otel' };

describe('traceContextFields', () => {
  it('should return an empty record for an absent span context', () => {
    // Act
    const actual = traceContextFields(undefined);

    // Assert
    actual.should.eql({});
  });

  it('should return an empty record for an invalid span context', () => {
    // Arrange - all-zero ids are not a valid span context
    const invalid: SpanContext = { traceId: '0'.repeat(32), spanId: '0'.repeat(16), traceFlags: 0 };

    // Act
    const actual = traceContextFields(invalid);

    // Assert
    actual.should.eql({});
  });

  it('should project a valid span context onto correlation fields', () => {
    // Act
    const actual = traceContextFields(VALID_SPAN_CONTEXT);

    // Assert
    actual.should.eql({
      span_id: VALID_SPAN_CONTEXT.spanId,
      trace_flags: VALID_SPAN_CONTEXT.traceFlags,
      trace_id: VALID_SPAN_CONTEXT.traceId,
    });
  });
});

describe('activeSpanContext', () => {
  it('should return undefined when no span is active', () => {
    // Act / Assert
    (activeSpanContext() === undefined).should.be.true();
  });
});

describe('createLoggerSignal', () => {
  it('should emit JSON with resource base, record attributes and injected trace correlation when active', async () => {
    // Arrange - a valid injected span context drives the pino mixin. Regression:
    // the mixin must hand pino a MUTABLE copy of the frozen trace-context value,
    // otherwise pino throws "not extensible" under Bun while decorating the line.
    const capture = makeCaptureStream();
    const signal = createLoggerSignal(
      true,
      { console: true, otlp: false },
      resource,
      capture,
      () => VALID_SPAN_CONTEXT,
    );

    // Act
    await expectOk(signal.sink.emit({ level: 'info', message: 'hello', attributes: { requestId: 'r1' } }));

    // Assert - one JSON line carrying the resource, attributes and correlation fields
    signal.active.should.be.true();
    capture.lines.length.should.eql(1);
    const emitted = JSON.parse(capture.lines[0] ?? '{}');
    emitted.msg.should.eql('hello');
    emitted.requestId.should.eql('r1');
    emitted['service.name'].should.eql('diene');
    emitted.trace_id.should.eql(VALID_SPAN_CONTEXT.traceId);
    emitted.span_id.should.eql(VALID_SPAN_CONTEXT.spanId);
    emitted.trace_flags.should.eql(VALID_SPAN_CONTEXT.traceFlags);
  });

  it('should omit trace correlation when no span is active (default span accessor)', async () => {
    // Arrange - no spanContext override falls back to activeSpanContext
    const capture = makeCaptureStream();
    const signal = createLoggerSignal(true, { console: true, otlp: false }, resource, capture);

    // Act
    await expectOk(signal.sink.emit({ level: 'info', message: 'plain' }));

    // Assert
    const emitted = JSON.parse(capture.lines[0] ?? '{}');
    ('trace_id' in emitted).should.be.false();
  });

  it('should be inactive and write nothing when disabled, defaulting the destination', async () => {
    // Arrange - no destination exercises the pino(options) branch
    const signal = createLoggerSignal(false, { console: false, otlp: false }, resource);

    // Act / Assert - a valid record is accepted but nothing is emitted
    signal.active.should.be.false();
    signal.otlpBridge.should.eql(OTLP_LOGS_BRIDGE_STATUS);
    await expectOk(signal.sink.emit({ level: 'info', message: 'silent' }));
  });

  it('should reject a malformed log record', async () => {
    // Arrange
    const signal = createLoggerSignal(true, { console: true, otlp: false }, resource, makeCaptureStream());

    // Act
    const error = await expectErr(signal.sink.emit({ level: 'nope', message: 'x' } as unknown as LogRecord));

    // Assert
    error.code.should.eql('invalid-input');
  });

  it('should flush the underlying logger', async () => {
    // Arrange
    const signal = createLoggerSignal(true, { console: true, otlp: false }, resource, makeCaptureStream());

    // Act / Assert
    await expectOk(signal.sink.flush());
  });
});

describe('PinoLoggerSink', () => {
  it('should surface an io error when the logger throws on emit', async () => {
    // Arrange
    const subject = new PinoLoggerSink(makeLogger({ emitThrows: true }).logger);

    // Act
    const error = await expectErr(subject.emit({ level: 'info', message: 'boom' }));

    // Assert
    error.code.should.eql('io');
    error.operation.should.eql('emit');
  });

  it('should surface an io error when the logger throws on flush', async () => {
    // Arrange
    const subject = new PinoLoggerSink(makeLogger({ flushThrows: true }).logger);

    // Act
    const error = await expectErr(subject.flush());

    // Assert
    error.code.should.eql('io');
    error.operation.should.eql('flush');
  });
});

describe('OTLP_LOGS_BRIDGE_STATUS', () => {
  it('should record the logs bridge as stubbed (S23)', () => {
    // Assert - the OTLP logs signal is a documented no-op until the JS SDK ships it
    OTLP_LOGS_BRIDGE_STATUS.should.eql('stubbed');
  });
});
