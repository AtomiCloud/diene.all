import { afterAll, beforeAll, describe, it } from 'bun:test';
import should from 'should';
import { GenericContainer, type StartedTestContainer, Wait } from 'testcontainers';
import { RedisKeyValueStore } from '../../src/adapters/kv/data/redis-kv-store';
import type { IKeyValueStore } from '../../src/lib/kv/interfaces';
import { namespacedKey } from '../../src/lib/kv/slug';

describe('RedisKeyValueStore (Testcontainers)', () => {
  let container: StartedTestContainer | undefined;
  let subject: IKeyValueStore | undefined;

  beforeAll(async () => {
    container = await new GenericContainer('redis:7.4.5-alpine')
      .withExposedPorts(6379)
      .withWaitStrategy(Wait.forLogMessage(/Ready to accept connections/))
      .start();
    subject = new RedisKeyValueStore({
      host: container.getHost(),
      port: container.getMappedPort(6379),
    });
  }, 120_000);

  afterAll(async () => {
    await subject?.close();
    await container?.stop();
  }, 120_000);

  it('should persist and retrieve a namespaced value', async () => {
    // Arrange
    const expected = 'hello';
    const key = namespacedKey('Bun Base', 'sample key');

    // Act
    await (subject as IKeyValueStore).set(key, expected);
    const actual = await (subject as IKeyValueStore).get(key);

    // Assert
    should(actual).equal(expected);
  });

  it('should return null for an unknown key', async () => {
    // Arrange
    const input = 'bun-base:missing';

    // Act
    const actual = await (subject as IKeyValueStore).get(input);

    // Assert
    should(actual).be.null();
  });
});
