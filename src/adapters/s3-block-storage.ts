import { Err, Ok, type Result } from '@atomicloud/diene.result';
import {
  type BlockStorage,
  type SaveInput,
  type SignedUrlOptions,
  StorageError,
  type StorageEntry,
  type StoredObject,
} from '../lib/presets/storage';

const DEFAULT_EXPIRES_IN = 900;

/** Percent-encode each path segment of an object key without touching the `/` separators. */
const encodeKey = (key: string): string =>
  key
    .split('/')
    .map(segment => encodeURIComponent(segment))
    .join('/');

/**
 * The one S3-compatible {@link BlockStorage} implementation, backed by Bun's
 * built-in `Bun.S3Client` — so the library adds NO extra runtime dependency for
 * object storage (the Bun runtime supplies the client). Works against any
 * S3-compatible endpoint: Tigris in prod, MinIO locally.
 *
 * The client is constructed lazily on first IO so the module imports cleanly
 * under Node (where `Bun` is absent) for dual-build/type-resolution checks;
 * `save`/`getSignedUrl` require the Bun runtime (Bun.S3Client) — this is a
 * Bun-only adapter by design.
 */
export class S3BlockStorage implements BlockStorage {
  private cachedClient?: Bun.S3Client;

  constructor(private readonly entry: StorageEntry) {}

  private client(): Bun.S3Client {
    if (this.cachedClient !== undefined) return this.cachedClient;
    this.cachedClient = new Bun.S3Client({
      accessKeyId: this.entry.accessKeyId,
      secretAccessKey: this.entry.secretAccessKey,
      region: this.entry.region,
      endpoint: this.entry.endpoint,
      bucket: this.entry.bucket,
      virtualHostedStyle: !this.entry.forcePathStyle,
    });
    return this.cachedClient;
  }

  async save(input: SaveInput): Promise<Result<StoredObject, StorageError>> {
    const options = input.contentType === undefined ? undefined : { type: input.contentType };
    try {
      await this.client().write(input.key, input.body, options);
      return Ok({ key: input.key, link: this.getLink(input.key) });
    } catch (error) {
      return Err(new StorageError(`failed to upload object "${input.key}"`, error));
    }
  }

  getLink(key: string): string {
    const encoded = encodeKey(key);
    const base = this.entry.endpoint.replace(/\/+$/, '');
    if (this.entry.forcePathStyle) {
      return `${base}/${this.entry.bucket}/${encoded}`;
    }
    const url = new URL(base);
    return `${url.protocol}//${this.entry.bucket}.${url.host}/${encoded}`;
  }

  getSignedUrl(key: string, options: SignedUrlOptions = {}): string {
    return this.client().presign(key, {
      expiresIn: options.expiresIn ?? DEFAULT_EXPIRES_IN,
      method: options.method ?? 'GET',
    });
  }
}
