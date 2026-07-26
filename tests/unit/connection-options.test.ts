import { describe, it } from 'bun:test';
import should from 'should';
import { toPostgresOptions, toRedisOptions, toS3Options } from '../../src/lib/connection-options';

describe('connection option mapping', () => {
  it.each([
    { configured: false, expected: false as const },
    { configured: true, expected: 'require' as const },
  ])('should map postgres ssl=$configured', ({ configured, expected }) => {
    // Arrange
    const entry = {
      database: 'consumer',
      host: 'postgres',
      password: 'secret',
      pool: { max: 8, min: 1 },
      port: 5432,
      ssl: configured,
      username: 'worker',
    };

    // Act
    const actual = toPostgresOptions(entry);

    // Assert
    should(actual).deepEqual({
      database: 'consumer',
      host: 'postgres',
      max: 8,
      min: 1,
      password: 'secret',
      port: 5432,
      ssl: expected,
      username: 'worker',
    });
  });

  it.each([
    { password: '', tls: false, expectedPassword: undefined, expectedTls: undefined },
    { password: 'secret', tls: true, expectedPassword: 'secret', expectedTls: {} },
  ])('should map redis password and tls settings', ({ password, tls, expectedPassword, expectedTls }) => {
    // Arrange
    const entry = { db: 2, host: 'redis', password, port: 6379, tls };

    // Act
    const actual = toRedisOptions(entry);

    // Assert
    should(actual).deepEqual({
      db: 2,
      host: 'redis',
      lazyConnect: true,
      password: expectedPassword,
      port: 6379,
      tls: expectedTls,
    });
  });

  it.each([
    { forcePathStyle: true, virtualHostedStyle: false },
    { forcePathStyle: false, virtualHostedStyle: true },
  ])('should map S3 path-style=$forcePathStyle', ({ forcePathStyle, virtualHostedStyle }) => {
    // Arrange
    const entry = {
      accessKeyId: 'key',
      bucket: 'bucket',
      endpoint: 'http://storage:9000',
      forcePathStyle,
      region: 'us-east-1',
      secretAccessKey: 'secret',
    };

    // Act
    const actual = toS3Options(entry);

    // Assert
    should(actual).deepEqual({
      accessKeyId: 'key',
      bucket: 'bucket',
      endpoint: 'http://storage:9000',
      region: 'us-east-1',
      secretAccessKey: 'secret',
      virtualHostedStyle,
    });
  });
});
