import { afterAll, beforeAll, describe, it } from 'bun:test';
import should from 'should';
import { GenericContainer, type StartedTestContainer, Wait } from 'testcontainers';
import type { IKeyValueStore } from '../../src/adapters/kv-store';
import { createRedisStore, persistSample } from '../../src/index';

describe('RedisKeyValueStore (Testcontainers)', () => {
  let container: StartedTestContainer | undefined;
  let subject: IKeyValueStore | undefined;

  beforeAll(async () => {
    container = await new GenericContainer('redis:7.4.5-alpine')
      .withExposedPorts(6379)
      .withWaitStrategy(Wait.forLogMessage(/Ready to accept connections/))
      .start();
    subject = createRedisStore({
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

    // Act
    const actual = await persistSample(subject as IKeyValueStore, 'Bun Base', 'sample key', expected);

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
