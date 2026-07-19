import { afterAll, beforeAll, describe, it } from 'bun:test';
import should from 'should';
import { GenericContainer, type StartedTestContainer, Wait } from 'testcontainers';
import { DoctorController } from '../../src/adapters/kv/api/doctor-controller';
import { GetController } from '../../src/adapters/kv/api/get-controller';
import { SeedController } from '../../src/adapters/kv/api/seed-controller';
import { SetController } from '../../src/adapters/kv/api/set-controller';
import { EXIT_OK } from '../../src/adapters/cli/exit-codes';
import { RedisKeyValueStore } from '../../src/adapters/kv/data/redis-kv-store';
import { DoctorService } from '../../src/lib/kv/doctor-service';
import { KvService } from '../../src/lib/kv/service';
import { FakePrompt, FakeShell, captureIo, captureProgress, captureSpinner } from '../helpers/fakes';

describe('CLI controllers against real Redis', () => {
  let container: StartedTestContainer | undefined;
  let store: RedisKeyValueStore | undefined;

  beforeAll(async () => {
    container = await new GenericContainer('redis:7.4.5-alpine')
      .withExposedPorts(6379)
      .withWaitStrategy(Wait.forLogMessage(/Ready to accept connections/))
      .start();
    store = new RedisKeyValueStore({ host: container.getHost(), port: container.getMappedPort(6379) });
  }, 120_000);

  afterAll(async () => {
    await store?.close();
    await container?.stop();
  }, 120_000);

  it('should round-trip through the set and get controllers', async () => {
    // Arrange
    const io = captureIo();
    const service = new KvService(store as RedisKeyValueStore);
    const set = new SetController(service, io);
    const get = new GetController(service, io, new FakePrompt('unused'), false);

    // Act
    const setCode = await set.handle('real', 'round-trip', 'hello', '60');
    const getCode = await get.handle('real', 'round-trip');

    // Assert
    should(setCode).equal(EXIT_OK);
    should(getCode).equal(EXIT_OK);
    should(io.successes.at(-1)).equal('hello');
  });

  it('should seed entries through the controller into real Redis', async () => {
    // Arrange
    const io = captureIo();
    const progress = captureProgress();
    const service = new KvService(store as RedisKeyValueStore);
    const seed = new SeedController(service, io, progress);

    // Act
    const actual = await seed.handle('real-seed', '3');

    // Assert
    should(actual).equal(EXIT_OK);
    should(await (store as RedisKeyValueStore).get('real-seed:sample-3')).equal('value-3');
    should(progress.ticks).equal(3);
  });

  it('should diagnose a real reachable Redis backend', async () => {
    // Arrange
    const io = captureIo();
    const spinner = captureSpinner();
    const doctor = new DoctorController(
      new DoctorService(store as RedisKeyValueStore, new FakeShell('integration-platform')),
      io,
      spinner,
    );

    // Act
    const actual = await doctor.handle();

    // Assert
    should(actual).equal(EXIT_OK);
    should(spinner.events.at(-1)).equal('succeed:key-value backend reachable');
  });
});
