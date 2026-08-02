import { afterAll, beforeAll, describe, it } from 'bun:test';
import type { TCPSocketListener } from 'bun';
import should from 'should';
import { GenericContainer, type StartedTestContainer, Wait } from 'testcontainers';
import type { IKeyValueStore } from '../../src/adapters/kv-store';
import { createRedisStore, persistSample } from '../../src/index';
import type { ILogger } from '../../src/lib/logger';

interface RecordedLog {
  readonly fields: Record<string, unknown>;
  readonly message: string;
}

interface RecordingLogger {
  readonly logger: ILogger;
  readonly errors: RecordedLog[];
  /** Resolves on the first error record, so a test awaits the event instead of sleeping. */
  readonly firstError: Promise<RecordedLog>;
}

function recordingLogger(): RecordingLogger {
  const errors: RecordedLog[] = [];
  let announce: (entry: RecordedLog) => void = () => undefined;
  const firstError = new Promise<RecordedLog>(resolve => {
    announce = resolve;
  });

  return {
    errors,
    firstError,
    logger: {
      info: () => undefined,
      warn: () => undefined,
      error: (fields, message) => {
        const entry = { fields, message };
        errors.push(entry);
        announce(entry);
      },
    },
  };
}

describe('RedisKeyValueStore (Testcontainers)', () => {
  let container: StartedTestContainer | undefined;
  let subject: IKeyValueStore | undefined;
  let observed: RecordingLogger | undefined;

  beforeAll(async () => {
    container = await new GenericContainer('redis:7.4.5-alpine')
      .withExposedPorts(6379)
      .withWaitStrategy(Wait.forLogMessage(/Ready to accept connections/))
      .start();
    observed = recordingLogger();
    subject = createRedisStore(
      {
        host: container.getHost(),
        port: container.getMappedPort(6379),
      },
      observed.logger,
    );
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

  it('should overwrite the value already stored under a key', async () => {
    // Arrange
    const expected = 'second';

    // Act
    await persistSample(subject as IKeyValueStore, 'Bun Base', 'overwrite', 'first');
    const actual = await persistSample(subject as IKeyValueStore, 'Bun Base', 'overwrite', expected);

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

  it('should log nothing while the connection is healthy', () => {
    // Act
    const actual = (observed as RecordingLogger).errors;

    // Assert
    should(actual).eql([]);
  });
});

describe('RedisKeyValueStore against an endpoint that is not Redis', () => {
  let rogue: TCPSocketListener | undefined;
  let subject: IKeyValueStore | undefined;

  afterAll(async () => {
    await subject?.close().catch(() => undefined);
    rogue?.stop(true);
  }, 30_000);

  it('should report the failure through the injected logger instead of the console', async () => {
    // Arrange — a socket that answers with bytes RESP cannot parse. The resulting error carries no
    // ECONNREFUSED code, so it takes the "unexpected" branch the adapter has to surface.
    const observed = recordingLogger();
    const listener: TCPSocketListener = Bun.listen({
      hostname: '127.0.0.1',
      port: 0,
      socket: {
        data: socket => {
          socket.write('this is not a RESP reply\r\n');
        },
      },
    });
    rogue = listener;
    subject = createRedisStore({ host: '127.0.0.1', port: listener.port }, observed.logger);

    // Act
    const attempt = subject.get('bun-base:protocol').catch(() => null);
    const actual = await observed.firstError;

    // Assert
    should(actual.message).equal('unexpected redis connection error');
    should(actual.fields.host).equal('127.0.0.1');
    should(actual.fields.port).equal(listener.port);
    should(actual.fields.reason).be.a.String();
    await attempt;
  }, 30_000);
});
