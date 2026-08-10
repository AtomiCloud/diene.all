import { describe, it } from 'bun:test';
import { type LogLevel, type LogRecord, validateLogRecord } from '@atomicloud/diene.interfaces';
import 'should';
import { expectErr, expectOk } from './support/result.js';

describe('validateLogRecord', () => {
  it.each<LogLevel>(['trace', 'debug', 'info', 'warn', 'error', 'fatal'])(
    'should accept the %s level and freeze the normalized record',
    async level => {
      // Act
      const actual = await expectOk(validateLogRecord({ level, message: 'hello' }));

      // Assert - attributes key is omitted entirely when none are supplied
      actual.level.should.eql(level);
      actual.message.should.eql('hello');
      Object.hasOwn(actual, 'attributes').should.be.false();
      Object.isFrozen(actual).should.be.true();
    },
  );

  it('should normalize and sort provided attributes', async () => {
    // Act
    const actual = await expectOk(validateLogRecord({ level: 'info', message: 'm', attributes: { b: 2, a: 1 } }));

    // Assert
    Object.keys(actual.attributes ?? {}).should.eql(['a', 'b']);
    Object.isFrozen(actual.attributes).should.be.true();
  });

  it.each([
    ['null', null as unknown as LogRecord],
    ['a primitive', 7 as unknown as LogRecord],
  ])('should reject a non-object record (%s)', async (_label, record) => {
    // Act
    const error = await expectErr(validateLogRecord(record));

    // Assert
    error.port.should.eql('logging');
    error.operation.should.eql('emit');
    error.message.should.match(/must be an object/);
  });

  it('should reject an invalid level with the level field', async () => {
    // Act
    const error = await expectErr(validateLogRecord({ level: 'critical' as unknown as LogLevel, message: 'm' }));

    // Assert
    error.message.should.match(/Log level is invalid/);
    error.details.should.eql({ field: 'level' });
  });

  it.each([
    ['non-string', 5 as unknown as string],
    ['blank', '   '],
    ['empty', ''],
  ])('should reject a blank message (%s)', async (_label, message) => {
    // Act
    const error = await expectErr(validateLogRecord({ level: 'info', message }));

    // Assert
    error.message.should.match(/must not be blank/);
    error.details.should.eql({ field: 'message' });
  });

  it('should propagate telemetry validation failure for bad attributes', async () => {
    // Act
    const error = await expectErr(
      validateLogRecord({
        level: 'warn',
        message: 'm',
        attributes: { a: {} as unknown as number },
      }),
    );

    // Assert - error surfaced under the logging port/emit operation
    error.port.should.eql('logging');
    error.operation.should.eql('emit');
    error.message.should.match(/finite primitives/);
  });
});
