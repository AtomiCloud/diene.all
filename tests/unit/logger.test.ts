import { describe, it } from 'bun:test';
import should from 'should';
import { createLogger, type ILogger, type LoggerConfig } from '../../src/lib/logger';

interface CapturedRecord {
  readonly msg: string;
  readonly level: number;
  readonly trace_id?: string;
  readonly span_id?: string;
  readonly trace_flags?: number;
}

function captureDestination(sink: string[]): LoggerConfig['destination'] {
  return {
    write: (line: string) => {
      sink.push(line);
    },
  };
}

function records(sink: readonly string[]): CapturedRecord[] {
  return sink.map(line => JSON.parse(line) as CapturedRecord);
}

const VALID_TRACE_ID = '0af7651916cd43dd8448eb211c80319c';
const VALID_SPAN_ID = 'b7ad6b7169203331';

describe('createLogger', () => {
  it('should return an independent logger on every call so there is no shared mutable state', () => {
    // Arrange
    const first: string[] = [];
    const second: string[] = [];

    // Act
    const subject = createLogger({ destination: captureDestination(first) });
    const other = createLogger({ destination: captureDestination(second), level: 'error' });
    subject.info({}, 'only first');
    other.info({}, 'dropped by the second logger level');

    // Assert
    should(records(first).map(record => record.msg)).eql(['only first']);
    should(second).eql([]);
  });

  it('should build a stdout logger when no configuration is supplied', () => {
    // Act
    const actual = createLogger();

    // Assert
    should(typeof actual.info).equal('function');
    should(typeof actual.warn).equal('function');
    should(typeof actual.error).equal('function');
  });

  it.each([
    { method: 'info' as const, expected: 30 },
    { method: 'warn' as const, expected: 40 },
    { method: 'error' as const, expected: 50 },
  ])('should emit $method records at pino level $expected', ({ method, expected }) => {
    // Arrange
    const sink: string[] = [];
    const subject: ILogger = createLogger({ destination: captureDestination(sink), level: 'debug' });

    // Act
    subject[method]({ field: 'value' }, `${method} message`);

    // Assert
    const [actual] = records(sink);
    should(actual?.level).equal(expected);
    should(actual?.msg).equal(`${method} message`);
  });

  it('should attach the active trace context to every record', () => {
    // Arrange
    const sink: string[] = [];
    const subject = createLogger({
      destination: captureDestination(sink),
      spanContext: () => ({ traceId: VALID_TRACE_ID, spanId: VALID_SPAN_ID, traceFlags: 1 }),
    });

    // Act
    subject.info({}, 'traced');

    // Assert
    const [actual] = records(sink);
    should(actual?.trace_id).equal(VALID_TRACE_ID);
    should(actual?.span_id).equal(VALID_SPAN_ID);
    should(actual?.trace_flags).equal(1);
  });

  it('should omit trace fields when there is no active span', () => {
    // Arrange
    const sink: string[] = [];
    const subject = createLogger({
      destination: captureDestination(sink),
      spanContext: () => undefined,
    });

    // Act
    subject.info({}, 'untraced');

    // Assert
    const [actual] = records(sink);
    should(actual).not.have.property('trace_id');
    should(actual).not.have.property('span_id');
  });

  it('should omit trace fields when the active span context is invalid', () => {
    // Arrange
    const sink: string[] = [];
    const subject = createLogger({
      destination: captureDestination(sink),
      spanContext: () => ({ traceId: '0'.repeat(32), spanId: '0'.repeat(16), traceFlags: 0 }),
    });

    // Act
    subject.info({}, 'invalid span');

    // Assert
    const [actual] = records(sink);
    should(actual).not.have.property('trace_id');
  });
});
