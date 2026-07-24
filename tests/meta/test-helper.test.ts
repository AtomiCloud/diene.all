import { afterAll, beforeAll, describe, expect, it } from 'bun:test';
import { S3BlockStorage } from '../../src/adapters/s3-block-storage';
import { cache } from '../../src/presets/cache';
import { kv } from '../../src/presets/kv';
import { postgres } from '../../src/presets/postgres';
import type { BlockStorage } from '../../src/presets/storage';
import { storage } from '../../src/presets/storage';
import {
  InMemoryBlockStorage,
  createS3Bucket,
  startCache,
  startKv,
  startPostgres,
  startStorage,
} from '../../src/test-helper';

// ─── the in-memory block-storage fake ────────────────────────────────────────────
describe('InMemoryBlockStorage', () => {
  it('saves a string body and reads it back', async () => {
    const fake = new InMemoryBlockStorage();
    const result = await fake.save({ key: 'a.txt', body: 'hello', contentType: 'text/plain' });
    expect(await result.isOk()).toBe(true);
    expect(fake.has('a.txt')).toBe(true);
    expect(fake.size).toBe(1);
    expect(new TextDecoder().decode(fake.read('a.txt')?.body)).toBe('hello');
    expect(fake.read('a.txt')?.contentType).toBe('text/plain');
  });

  it('accepts ArrayBuffer and Uint8Array bodies', async () => {
    const fake = new InMemoryBlockStorage();
    await fake.save({ key: 'buf', body: new TextEncoder().encode('ab').buffer });
    await fake.save({ key: 'u8', body: new Uint8Array([1, 2, 3]) });
    expect(fake.read('buf')?.body.length).toBe(2);
    expect(Array.from(fake.read('u8')?.body ?? [])).toEqual([1, 2, 3]);
  });

  it('builds a deterministic link (default and custom base URL, encoded)', () => {
    expect(new InMemoryBlockStorage().getLink('a b/c.png')).toBe('memory://block-storage/a%20b/c.png');
    expect(new InMemoryBlockStorage('memory://cdn/').getLink('x.png')).toBe('memory://cdn/x.png');
  });

  it('signs a URL carrying method and expiry (default and custom)', () => {
    const fake = new InMemoryBlockStorage();
    expect(fake.getSignedUrl('a.txt')).toContain('X-Expires=900');
    const custom = fake.getSignedUrl('a.txt', { expiresIn: 60, method: 'PUT' });
    expect(custom).toContain('X-Method=PUT');
    expect(custom).toContain('X-Expires=60');
  });

  it('clears stored objects', async () => {
    const fake = new InMemoryBlockStorage();
    await fake.save({ key: 'a', body: 'x' });
    fake.clear();
    expect(fake.size).toBe(0);
    expect(fake.has('a')).toBe(false);
    expect(fake.read('a')).toBeUndefined();
  });
});

// ─── Testcontainers glue — booting real containers ───────────────────────────────
describe('Testcontainers glue emits schema-valid blocks', () => {
  let pg: Awaited<ReturnType<typeof startPostgres>>;
  let cacheC: Awaited<ReturnType<typeof startCache>>;
  let kvC: Awaited<ReturnType<typeof startKv>>;
  let storageC: Awaited<ReturnType<typeof startStorage>>;

  beforeAll(async () => {
    [pg, cacheC, kvC, storageC] = await Promise.all([
      startPostgres({ key: 'MAIN' }),
      startCache(),
      startKv({ key: 'SESSION' }),
      startStorage({ bucket: 'media' }),
    ]);
  }, 240_000);

  afterAll(async () => {
    await Promise.all([pg?.stop(), cacheC?.stop(), kvC?.stop(), storageC?.stop()]);
  });

  it('postgres glue emits a block valid against the postgres preset', () => {
    expect(pg.key).toBe('MAIN');
    expect(postgres.safeParse(pg.block).success).toBe(true);
  });

  it('cache glue emits a block valid against the cache preset', () => {
    expect(cache.safeParse(cacheC.block).success).toBe(true);
  });

  it('kv glue emits a block valid against the kv preset (keyed name honored)', () => {
    expect(kvC.key).toBe('SESSION');
    expect(kv.safeParse(kvC.block).success).toBe(true);
  });

  it('storage glue emits a block valid against the storage preset', () => {
    expect(storage.safeParse(storageC.block).success).toBe(true);
  });

  it('createS3Bucket throws on a rejected request (bad credentials)', async () => {
    const { endpoint, region } = storageC.entry;
    await expect(createS3Bucket(endpoint, region, 'wrong', 'wrong', 'denied-bucket')).rejects.toThrow();
  });

  // ── contract parity: the fake and the real S3 impl honor the same BlockStorage surface ──
  it('the fake and the S3 impl agree on the save→link contract', async () => {
    const s3 = new S3BlockStorage(storageC.entry);
    const check = async (impl: BlockStorage, label: string) => {
      const key = `parity/${label}.txt`;
      const result = await impl.save({ key, body: 'parity-data' });
      expect(await result.isOk()).toBe(true);
      const stored = await result.unwrap();
      expect(stored.key).toBe(key);
      // save's returned link is exactly what getLink reports (both impls)
      expect(stored.link).toBe(impl.getLink(key));
      // signed URL carries the object key
      expect(impl.getSignedUrl(key)).toContain(key);
    };
    await check(new InMemoryBlockStorage(), 'fake');
    await check(s3, 's3');
  });
});
