import { describe, expect, it } from 'bun:test';
import { cache, cacheEntry } from '../../src/presets/cache';
import { kv, kvEntry } from '../../src/presets/kv';
import { postgres, postgresEntry } from '../../src/presets/postgres';
import { redisConnectionEntry } from '../../src/presets/redis';
import { StorageError, storage, storageEntry } from '../../src/presets/storage';

const pgEntry = {
  host: 'db.host',
  port: 5432,
  database: 'app',
  username: 'app',
  password: '',
  ssl: false,
  pool: { min: 0, max: 10 },
};

const redisEntry = { host: 'r.host', port: 6379, password: '', db: 0, tls: false };

const s3Entry = {
  endpoint: 'https://fly.storage.tigris.dev',
  region: 'auto',
  bucket: 'app',
  accessKeyId: '',
  secretAccessKey: '',
  forcePathStyle: false,
};

describe('postgres preset', () => {
  it('accepts a keyed block with an UPPERCASE connection name', () => {
    expect(postgres.safeParse({ MAIN: pgEntry }).success).toBe(true);
  });

  it('supports keyed multi-instance (a second pool is data, not schema)', () => {
    expect(postgres.safeParse({ MAIN: pgEntry, REPLICA: { ...pgEntry, host: 'ro.host' } }).success).toBe(true);
  });

  it('rejects a lowercase connection name (R14 UPPERCASE)', () => {
    expect(postgres.safeParse({ main: pgEntry }).success).toBe(false);
  });

  it('rejects a hyphenated connection name', () => {
    expect(postgres.safeParse({ 'MAIN-1': pgEntry }).success).toBe(false);
  });

  it('rejects an out-of-range port', () => {
    expect(postgresEntry.safeParse({ ...pgEntry, port: 70000 }).success).toBe(false);
  });

  it('rejects a missing required field', () => {
    const { host, ...withoutHost } = pgEntry;
    void host;
    expect(postgresEntry.safeParse(withoutHost).success).toBe(false);
  });

  it('accepts a blank password (secret blank-in-yaml, R14/M33)', () => {
    expect(postgresEntry.safeParse({ ...pgEntry, password: '' }).success).toBe(true);
  });

  it('rejects a zero max pool size', () => {
    expect(postgresEntry.safeParse({ ...pgEntry, pool: { min: 0, max: 0 } }).success).toBe(false);
  });
});

describe('cache and kv presets (shared Redis connection shape, distinct blocks)', () => {
  it('cache accepts a valid Redis connection', () => {
    expect(cache.safeParse({ MAIN: redisEntry }).success).toBe(true);
  });

  it('kv accepts a valid Redis connection', () => {
    expect(kv.safeParse({ SESSION: redisEntry }).success).toBe(true);
  });

  it('cache and kv share the entry schema instance', () => {
    expect(cacheEntry).toBe(redisConnectionEntry);
    expect(kvEntry).toBe(redisConnectionEntry);
  });

  it('rejects a negative logical db index', () => {
    expect(redisConnectionEntry.safeParse({ ...redisEntry, db: -1 }).success).toBe(false);
  });

  it('rejects a lowercase cache key', () => {
    expect(cache.safeParse({ main: redisEntry }).success).toBe(false);
  });
});

describe('storage preset', () => {
  it('accepts a valid S3-compatible endpoint block', () => {
    expect(storage.safeParse({ MAIN: s3Entry }).success).toBe(true);
  });

  it('accepts blank access keys (secret blank-in-yaml)', () => {
    expect(storageEntry.safeParse({ ...s3Entry, accessKeyId: '', secretAccessKey: '' }).success).toBe(true);
  });

  it('rejects an empty endpoint', () => {
    expect(storageEntry.safeParse({ ...s3Entry, endpoint: '' }).success).toBe(false);
  });

  it('rejects a missing forcePathStyle', () => {
    const { forcePathStyle, ...withoutFlag } = s3Entry;
    void forcePathStyle;
    expect(storageEntry.safeParse(withoutFlag).success).toBe(false);
  });
});

describe('StorageError', () => {
  it('carries a message and an optional cause', () => {
    const cause = new Error('boom');
    const withCause = new StorageError('upload failed', cause);
    expect(withCause.name).toBe('StorageError');
    expect(withCause.message).toBe('upload failed');
    expect(withCause.cause).toBe(cause);
    expect(new StorageError('no cause').cause).toBeUndefined();
  });
});
