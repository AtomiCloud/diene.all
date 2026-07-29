import { afterAll, beforeAll, describe, it } from 'bun:test';
import { InMemoryLoggerSink, InMemoryMetricsCollector } from '@atomicloud/diene.e2e/interfaces/test-helper';
import { defaultOtelBlock, initOtel, type OtelRuntime } from '@atomicloud/diene.e2e/otel';
import { InMemoryTraceEmitter } from '@atomicloud/diene.e2e/otel/test-helper';
import { Err } from '@atomicloud/diene.e2e/result';
import {
  startCache,
  startPostgres,
  startStorage,
  type StartedPreset,
} from '@atomicloud/diene.e2e/standard-config/test-helper';
import {
  StorageError,
  type PostgresEntry,
  type RedisConnectionEntry,
  type StorageEntry,
  type StoredObject,
} from '@atomicloud/diene.e2e/standard-config';
import type Redis from 'ioredis';
import should from 'should';
import { buildPostgresAdapters, PostgresAdapter, type PostgresClient } from '../../src/adapters/postgres';
import { buildRedisAdapters, RedisAdapter } from '../../src/adapters/redis';
import { RedisStreamsTransport } from '../../src/adapters/redis-streams';
import { buildStorageAdapters, StorageAdapter } from '../../src/adapters/storage';
import { Aes256GcmEncryptor } from '../../src/lib/encryption';

const identity = {
  landscape: 'integration',
  module: 'worker',
  platform: 'diene',
  service: 'consumer-test',
  version: '1.0.0',
};

let telemetry: OtelRuntime | undefined;
let postgresContainer: StartedPreset<PostgresEntry> | undefined;
let redisContainer: StartedPreset<RedisConnectionEntry> | undefined;
let storageContainer: StartedPreset<StorageEntry> | undefined;
let postgresAdapter: PostgresAdapter | undefined;
let redisAdapter: RedisAdapter | undefined;
let storageAdapter: StorageAdapter | undefined;

beforeAll(async () => {
  const [postgresStarted, redisStarted, storageStarted] = await Promise.all([
    startPostgres(),
    startCache(),
    startStorage(),
  ]);
  postgresContainer = postgresStarted;
  redisContainer = redisStarted;
  storageContainer = storageStarted;
  telemetry = initOtel(defaultOtelBlock, identity, {
    seams: {
      logger: new InMemoryLoggerSink(),
      metrics: new InMemoryMetricsCollector(),
      traces: new InMemoryTraceEmitter(),
    },
  });
  postgresAdapter = buildPostgresAdapters(postgresStarted.block, telemetry.tracer).get('MAIN');
  redisAdapter = buildRedisAdapters(redisStarted.block, telemetry.tracer, 'cache').get('MAIN');
  storageAdapter = buildStorageAdapters(storageStarted.block, telemetry.tracer).get('MAIN');
  await redisAdapter?.connect().match({ err: error => Promise.reject(error), ok: () => undefined });
}, 120_000);

afterAll(async () => {
  try {
    await postgresAdapter?.close();
  } catch {}
  try {
    await redisAdapter?.close();
  } catch {
    redisAdapter?.client.disconnect();
  }
  try {
    await telemetry?.shutdown();
  } catch {}
  try {
    await postgresContainer?.stop();
  } catch {}
  try {
    await redisContainer?.stop();
  } catch {}
  try {
    await storageContainer?.stop();
  } catch {}
}, 120_000);

describe('PostgresAdapter', () => {
  it('should run repository, migration, and idempotency operations against Postgres', async () => {
    // Arrange
    const subject = postgresAdapter as PostgresAdapter;
    await subject
      .query(
        'CREATE TABLE processed_messages (id TEXT PRIMARY KEY, payload TEXT, object_key TEXT, created_at TIMESTAMPTZ); CREATE TABLE seed_records (id TEXT PRIMARY KEY, value TEXT)',
      )
      .match({ err: error => Promise.reject(error), ok: () => undefined });
    await subject.query('CREATE TABLE IF NOT EXISTS adapter_notice_probe (id TEXT)').unwrap();
    await subject.query('CREATE TABLE IF NOT EXISTS adapter_notice_probe (id TEXT)').unwrap();

    // Act
    const ping = await subject.ping().isOk();
    const first = await subject
      .insert({ createdAt: '2026-07-25T06:30:00Z', id: 'message', objectKey: 'objects/message', payload: 'one' })
      .unwrap();
    const duplicate = await subject
      .insert({ createdAt: '2026-07-25T06:30:00Z', id: 'message', objectKey: 'objects/message', payload: 'one' })
      .unwrap();
    const total = await subject.countProcessedMessages().unwrap();
    const selected = await subject.countProcessedMessages('message').unwrap();
    const firstSeed = await subject.insertSeed({ id: 'seed', value: 'one' }).unwrap();
    const duplicateSeed = await subject.insertSeed({ id: 'seed', value: 'one' }).unwrap();
    const ids = await subject.listSeedIds().unwrap();
    const seedCount = await subject.countSeeds().unwrap();

    // Assert
    should(ping).equal(true);
    should(first).equal(true);
    should(duplicate).equal(false);
    should(total).equal(1);
    should(selected).equal(1);
    should(firstSeed).equal(true);
    should(duplicateSeed).equal(false);
    should([...ids]).deepEqual(['seed']);
    should(seedCount).equal(1);
  });

  it('should map a query exception to AdapterError', async () => {
    // Arrange
    const failingClient = {
      unsafe: () => Promise.reject(new Error('postgres unavailable')),
    } as unknown as PostgresClient;
    const subject = new PostgresAdapter(failingClient, (telemetry as OtelRuntime).tracer, 'FAILURE');

    // Act
    const actual = await subject.query('SELECT 1').match({ err: error => error, ok: () => undefined });

    // Assert
    should(actual?.operation).equal('postgres.query');
    should(actual?.cause).be.instanceOf(Error);
  });
});

describe('RedisAdapter and RedisStreamsTransport', () => {
  it('should persist values and process consumer-group pending entries against Redis', async () => {
    // Arrange
    const redis = redisAdapter as RedisAdapter;
    const config = {
      batchSize: 10,
      blockMs: 10,
      consumerGroup: 'integration',
      consumerName: 'worker-one',
      idleMs: 0,
      stream: `integration-${crypto.randomUUID()}`,
    };
    const transport = new RedisStreamsTransport(redis.client, (telemetry as OtelRuntime).tracer, config);

    // Act
    const ping = await redis.ping().isOk();
    const firstSet = await redis.setIfAbsent('integration:key', 'value').unwrap();
    const duplicateSet = await redis.setIfAbsent('integration:key', 'other').unwrap();
    const value = await redis.get('integration:key').unwrap();
    const missing = await redis.get('integration:missing').unwrap();
    await transport.ensureGroup().unwrap();
    await transport.ensureGroup().unwrap();
    const streamId = await transport.publish('payload').unwrap();
    const consumed = await transport.consume().unwrap();
    const reclaimed = await transport.reclaimPending().unwrap();
    const acknowledged = await transport.acknowledge(streamId).unwrap();
    const empty = await transport.consume().unwrap();

    // Assert
    should(ping).equal(true);
    should(firstSet).equal(true);
    should(duplicateSet).equal(false);
    should(value).equal('value');
    should(missing).be.null();
    should(consumed).deepEqual([{ id: streamId, payload: 'payload' }]);
    should(reclaimed).deepEqual([{ id: streamId, payload: 'payload' }]);
    should(acknowledged).equal(1);
    should(empty).deepEqual([]);
  });

  it('should map Redis command failures to adapter errors', async () => {
    // Arrange
    const failing = new Proxy({}, { get: () => () => Promise.reject(new Error('redis unavailable')) }) as Redis;
    const redis = new RedisAdapter(failing, (telemetry as OtelRuntime).tracer, 'FAILURE', 'kv');
    const transport = new RedisStreamsTransport(failing, (telemetry as OtelRuntime).tracer, {
      batchSize: 1,
      blockMs: 1,
      consumerGroup: 'failure',
      consumerName: 'failure',
      idleMs: 0,
      stream: 'failure',
    });

    // Act
    const errors = await Promise.all([
      redis.connect().unwrapErr(),
      redis.ping().unwrapErr(),
      redis.setIfAbsent('key', 'value').unwrapErr(),
      redis.get('key').unwrapErr(),
      transport.ensureGroup().unwrapErr(),
      transport.publish('payload').unwrapErr(),
      transport.consume().unwrapErr(),
      transport.reclaimPending().unwrapErr(),
      transport.acknowledge('1-0').unwrapErr(),
    ]);

    // Assert
    should(errors.map(error => error.operation)).deepEqual([
      'redis.connect',
      'redis.ping',
      'redis.set',
      'redis.get',
      'redis-streams.ensure-group',
      'redis-streams.publish',
      'redis-streams.consume',
      'redis-streams.reclaim',
      'redis-streams.acknowledge',
    ]);
  });
});

describe('StorageAdapter and IEncryptor integration', () => {
  it('should list, encrypt, upload, and link an object against MinIO', async () => {
    // Arrange
    const subject = storageAdapter as StorageAdapter;
    const key = `integration/${crypto.randomUUID()}.txt`;
    const encryptor = new Aes256GcmEncryptor('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=');

    // Act
    const before = await subject.list().unwrap();
    const encrypted = await encryptor.encrypt('integration-payload').unwrap();
    const stored = await subject.save({ body: encrypted, contentType: 'text/plain', key }).unwrap();
    const contents = await subject.client.file(key).text();
    const decrypted = await encryptor.decrypt(contents).unwrap();
    const link = subject.getLink(key);
    const signed = subject.getSignedUrl(key, 60);

    // Assert
    should(before).be.aboveOrEqual(0);
    should(stored.key).equal(key);
    should(decrypted).equal('integration-payload');
    should(link).containEql(key);
    should(signed).containEql(key);
  });

  it('should map storage list and upload failures to AdapterError', async () => {
    // Arrange
    const entry = (storageContainer as StartedPreset<StorageEntry>).entry;
    const failingStorage = {
      getLink: (key: string) => `failed://${key}`,
      getSignedUrl: (key: string) => `failed://${key}`,
      save: () => Promise.resolve(Err<StoredObject, StorageError>(new StorageError('upload unavailable'))),
    };
    const failingClient = { list: () => Promise.reject(new Error('list unavailable')) } as unknown as Bun.S3Client;
    const subject = new StorageAdapter(
      entry,
      (telemetry as OtelRuntime).tracer,
      'FAILURE',
      failingStorage,
      failingClient,
    );

    // Act
    const listError = await subject.list().unwrapErr();
    const saveError = await subject.save({ body: 'payload', key: 'key' }).unwrapErr();
    const link = subject.getLink('key');
    const signed = subject.getSignedUrl('key');

    // Assert
    should(listError.operation).equal('storage.list');
    should(saveError.operation).equal('storage.save');
    should(link).equal('failed://key');
    should(signed).equal('failed://key');
  });
});
