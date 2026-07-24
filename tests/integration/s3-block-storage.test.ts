import { afterAll, beforeAll, describe, expect, it } from 'bun:test';
import { S3BlockStorage } from '../../src/adapters/s3-block-storage';
import type { StorageEntry } from '../../src/presets/storage';
import { type StartedPreset, startStorage } from '../../src/test-helper';

const tigrisStyle: StorageEntry = {
  endpoint: 'https://fly.storage.tigris.dev',
  region: 'auto',
  bucket: 'media',
  accessKeyId: 'ak',
  secretAccessKey: 'sk',
  forcePathStyle: false,
};

const pathStyle: StorageEntry = {
  endpoint: 'http://minio.local:9000/',
  region: 'us-east-1',
  bucket: 'app',
  accessKeyId: 'ak',
  secretAccessKey: 'sk',
  forcePathStyle: true,
};

describe('S3BlockStorage.getLink (pure)', () => {
  it('builds a path-style URL for forcePathStyle endpoints', () => {
    const storage = new S3BlockStorage(pathStyle);
    expect(storage.getLink('folder/pic.png')).toBe('http://minio.local:9000/app/folder/pic.png');
  });

  it('builds a virtual-hosted URL otherwise', () => {
    const storage = new S3BlockStorage(tigrisStyle);
    expect(storage.getLink('folder/pic.png')).toBe('https://media.fly.storage.tigris.dev/folder/pic.png');
  });

  it('percent-encodes each path segment but not the separators', () => {
    const storage = new S3BlockStorage(pathStyle);
    expect(storage.getLink('a b/c+d.png')).toBe('http://minio.local:9000/app/a%20b/c%2Bd.png');
  });
});

describe('S3BlockStorage against a real MinIO container', () => {
  let started: StartedPreset<StorageEntry>;
  let storage: S3BlockStorage;

  beforeAll(async () => {
    started = await startStorage({ bucket: 'media' });
    storage = new S3BlockStorage(started.entry);
  }, 180_000);

  afterAll(async () => {
    await started?.stop();
  });

  it('uploads an object and returns Ok with its stored handle', async () => {
    const result = await storage.save({
      key: 'docs/hello.txt',
      body: 'hello-standard-config',
      contentType: 'text/plain',
    });
    expect(await result.isOk()).toBe(true);
    const stored = await result.unwrap();
    expect(stored.key).toBe('docs/hello.txt');
    expect(stored.link).toBe(storage.getLink('docs/hello.txt'));

    // read the object back through a fresh client to prove the upload landed
    const client = new Bun.S3Client({
      accessKeyId: started.entry.accessKeyId,
      secretAccessKey: started.entry.secretAccessKey,
      region: started.entry.region,
      endpoint: started.entry.endpoint,
      bucket: started.entry.bucket,
      virtualHostedStyle: false,
    });
    expect(await client.file('docs/hello.txt').text()).toBe('hello-standard-config');
  });

  it('signs a time-limited URL that carries the key (client already warm)', () => {
    const url = storage.getSignedUrl('docs/hello.txt', { expiresIn: 60, method: 'GET' });
    expect(url).toContain('docs/hello.txt');
    expect(url).toContain('X-Amz-Signature');
    expect(url).toContain('X-Amz-Expires=60');
  });

  it('returns Err<StorageError> when the endpoint is unreachable', async () => {
    const broken = new S3BlockStorage({ ...started.entry, endpoint: 'http://127.0.0.1:1' });
    const result = await broken.save({ key: 'nope.txt', body: 'x' });
    expect(await result.isErr()).toBe(true);
  });
});
