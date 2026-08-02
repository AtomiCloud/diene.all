import { describe, it } from 'bun:test';
import should from 'should';
import { parseRedisEnvironment, type RedisConfigResult, type RedisEnvironment } from '../../src/lib/redis-config';

const DEFAULT_PORT = 6379;

function parse(input: RedisEnvironment): RedisConfigResult {
  return parseRedisEnvironment(input);
}

describe('parseRedisEnvironment', () => {
  it.each([
    { label: 'no variables at all', input: {} },
    { label: 'an empty host', input: { REDIS_HOST: '' } },
    { label: 'a whitespace-only host', input: { REDIS_HOST: '   ' } },
    { label: 'a tab-only host', input: { REDIS_HOST: '\t\n' } },
    { label: 'an explicitly undefined host', input: { REDIS_HOST: undefined } },
    { label: 'a port but no host', input: { REDIS_PORT: '6380' } },
  ])('should report no connection for $label', ({ input }) => {
    // Act
    const actual = parse(input);

    // Assert
    should(actual.ok).be.true();
    should(actual.ok && actual.connection).be.undefined();
  });

  it.each([
    { label: 'an unset port', input: { REDIS_HOST: 'cache' }, expected: DEFAULT_PORT },
    { label: 'a blank port', input: { REDIS_HOST: 'cache', REDIS_PORT: '   ' }, expected: DEFAULT_PORT },
    { label: 'an explicit port', input: { REDIS_HOST: 'cache', REDIS_PORT: '6380' }, expected: 6380 },
    { label: 'a padded port', input: { REDIS_HOST: 'cache', REDIS_PORT: ' 6380 ' }, expected: 6380 },
    { label: 'the lowest port', input: { REDIS_HOST: 'cache', REDIS_PORT: '1' }, expected: 1 },
    { label: 'the highest port', input: { REDIS_HOST: 'cache', REDIS_PORT: '65535' }, expected: 65535 },
  ])('should resolve $label to port $expected', ({ input, expected }) => {
    // Act
    const actual = parse(input);

    // Assert
    should(actual.ok && actual.connection).eql({ host: 'cache', port: expected });
  });

  it('should trim surrounding whitespace from the host', () => {
    // Arrange
    const input = { REDIS_HOST: '  cache  ' };
    const expected = { host: 'cache', port: DEFAULT_PORT };

    // Act
    const actual = parse(input);

    // Assert
    should(actual.ok && actual.connection).eql(expected);
  });

  it.each([
    { input: { REDIS_PORT: 'abc' }, expected: 'REDIS_PORT must be a whole number, for example 6379' },
    { input: { REDIS_PORT: '6379.5' }, expected: 'REDIS_PORT must be a whole number, for example 6379' },
    { input: { REDIS_PORT: '-1' }, expected: 'REDIS_PORT must be a whole number, for example 6379' },
    { input: { REDIS_PORT: '0' }, expected: 'REDIS_PORT must be between 1 and 65535' },
    { input: { REDIS_PORT: '65536' }, expected: 'REDIS_PORT must be between 1 and 65535' },
  ])('should reject REDIS_PORT "$input.REDIS_PORT" with a named issue', ({ input, expected }) => {
    // Act
    const actual = parse(input);

    // Assert
    should(actual.ok).be.false();
    should(!actual.ok && actual.issues).eql([expected]);
  });

  it('should reject an invalid port even when a valid host is present', () => {
    // Arrange
    const input = { REDIS_HOST: 'cache', REDIS_PORT: 'not-a-port' };

    // Act
    const actual = parse(input);

    // Assert
    should(actual.ok).be.false();
  });
});
