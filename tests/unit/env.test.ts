import { describe, it } from 'bun:test';
import should from 'should';
import { applyEnvOverrides, NESTING_SEPARATOR } from '../../src/lib/env.js';
import type { ConfigRecord } from '../../src/lib/merge.js';

const PREFIX = 'ATOMI_';

describe('NESTING_SEPARATOR', () => {
  it('should be the double underscore', () => {
    // Arrange / Act / Assert
    should(NESTING_SEPARATOR).equal('__');
  });
});

describe('applyEnvOverrides — name matching (snake ↔ pascal/camel/kebab)', () => {
  it.each([
    { envKey: 'ATOMI_SERVER__MAX_RETRIES', matched: 'maxRetries' },
    { envKey: 'ATOMI_SERVER__MAXRETRIES', matched: 'maxRetries' },
    { envKey: 'ATOMI_server__max_retries', matched: 'maxRetries' },
  ])('should match $envKey onto the existing camelCase key', ({ envKey, matched }) => {
    // Arrange
    const base: ConfigRecord = { server: { maxRetries: 1 } };

    // Act
    const actual = applyEnvOverrides(base, { [envKey]: '9' }, PREFIX) as { server: Record<string, unknown> };

    // Assert
    should(actual.server[matched]).equal(9);
    should(Object.keys(actual.server)).deepEqual(['maxRetries']);
  });
});

describe('applyEnvOverrides — coercion and unset', () => {
  it('should coerce booleans and numbers while runtime wins', () => {
    // Arrange
    const base: ConfigRecord = { server: { port: 80, debug: false } };
    const env = { ATOMI_SERVER__PORT: '8080', ATOMI_SERVER__DEBUG: 'true' };

    // Act
    const actual = applyEnvOverrides(base, env, PREFIX) as { server: { port: number; debug: boolean } };

    // Assert
    should(actual.server.port).equal(8080);
    should(actual.server.debug).equal(true);
  });

  it('should skip a blank env value (M33 unset), leaving the base value', () => {
    // Arrange
    const base: ConfigRecord = { server: { host: 'keep' } };

    // Act
    const actual = applyEnvOverrides(base, { ATOMI_SERVER__HOST: '' }, PREFIX) as { server: { host: string } };

    // Assert
    should(actual.server.host).equal('keep');
  });

  it('should ignore variables without the prefix and undefined values', () => {
    // Arrange
    const base: ConfigRecord = { a: 1 };

    // Act
    const actual = applyEnvOverrides(base, { OTHER__A: '5', ATOMI_A: undefined }, PREFIX);

    // Assert
    should(actual).deepEqual({ a: 1 });
  });

  it('should ignore a malformed key with an empty segment', () => {
    // Arrange
    const base: ConfigRecord = { a: 1 };

    // Act
    const actual = applyEnvOverrides(base, { ATOMI_A__: '5' }, PREFIX);

    // Assert
    should(actual).deepEqual({ a: 1 });
  });
});

describe('applyEnvOverrides — nested and indexed-list encoding', () => {
  it('should create a new nested object for an absent key', () => {
    // Arrange
    const base: ConfigRecord = {};

    // Act
    const actual = applyEnvOverrides(base, { ATOMI_A__B__C: '1' }, PREFIX) as { a: { b: { c: number } } };

    // Assert
    should(actual.a.b.c).equal(1);
  });

  it('should set array elements by index into an existing array', () => {
    // Arrange
    const base: ConfigRecord = { endpoints: ['zero', 'one'] };
    const env = { ATOMI_ENDPOINTS__0: 'primary', ATOMI_ENDPOINTS__2: 'third' };

    // Act
    const actual = applyEnvOverrides(base, env, PREFIX) as { endpoints: unknown[] };

    // Assert
    should(actual.endpoints).deepEqual(['primary', 'one', 'third']);
  });

  it('should create a fresh array when the next segment is numeric', () => {
    // Arrange
    const base: ConfigRecord = {};

    // Act
    const actual = applyEnvOverrides(base, { ATOMI_LIST__0: 'a', ATOMI_LIST__1: 'b' }, PREFIX) as { list: unknown[] };

    // Assert
    should(actual.list).deepEqual(['a', 'b']);
  });

  it('should build nested objects/arrays through a numeric-then-key path', () => {
    // Arrange
    const base: ConfigRecord = {};

    // Act
    const actual = applyEnvOverrides(base, { ATOMI_ITEMS__0__NAME: 'first' }, PREFIX) as {
      items: Array<{ name: string }>;
    };

    // Assert
    should(actual.items[0]?.name).equal('first');
  });

  it('should ignore a non-numeric segment addressed into an array', () => {
    // Arrange
    const base: ConfigRecord = { list: ['a'] };

    // Act
    const actual = applyEnvOverrides(base, { ATOMI_LIST__FOO: 'x' }, PREFIX) as { list: unknown[] };

    // Assert
    should(actual.list).deepEqual(['a']);
  });

  it('should ignore an index beyond the guard bound', () => {
    // Arrange
    const base: ConfigRecord = { list: [] as unknown[] };

    // Act
    const actual = applyEnvOverrides(base, { ATOMI_LIST__5000: 'x' }, PREFIX) as { list: unknown[] };

    // Assert
    should(actual.list).deepEqual([]);
  });

  it('should not mutate the input object', () => {
    // Arrange
    const base: ConfigRecord = { server: { port: 80 } };

    // Act
    applyEnvOverrides(base, { ATOMI_SERVER__PORT: '9090' }, PREFIX);

    // Assert
    should(base).deepEqual({ server: { port: 80 } });
  });
});
