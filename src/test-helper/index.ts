import { createHash, createHmac } from 'node:crypto';
import { Ok, type Result } from '@atomicloud/diene.result';
import type { StartedTestContainer } from 'testcontainers';
import type { PostgresEntry } from '../presets/postgres';
import type { RedisConnectionEntry } from '../presets/redis';
import type {
  BlockStorage,
  SaveInput,
  SignedUrlOptions,
  StorageEntry,
  StorageError,
  StoredObject,
} from '../presets/storage';

// ─── In-memory block-storage fake ───────────────────────────────────────────────
// A dependency-free {@link BlockStorage} for UNIT tiers — deterministic links, no
// containers, no Bun runtime. Contract-parity with the real S3 impl is proven in
// the meta tier against a MinIO Testcontainer.

const encodeKey = (key: string): string =>
  key
    .split('/')
    .map(segment => encodeURIComponent(segment))
    .join('/');

const toBytes = (body: Uint8Array | ArrayBuffer | string): Uint8Array => {
  if (typeof body === 'string') return new TextEncoder().encode(body);
  if (body instanceof ArrayBuffer) return new Uint8Array(body);
  return body;
};

/** A stored blob, exposed for assertions. */
export interface StoredBlob {
  body: Uint8Array;
  contentType?: string;
}

/**
 * In-memory {@link BlockStorage} fake. `save` retains bytes in a `Map`; `getLink`
 * builds a deterministic `memory://` URL; `getSignedUrl` appends signature query
 * params so tests can assert expiry/method wiring without a real signer.
 */
export class InMemoryBlockStorage implements BlockStorage {
  private readonly store = new Map<string, StoredBlob>();

  constructor(private readonly baseUrl: string = 'memory://block-storage') {}

  async save(input: SaveInput): Promise<Result<StoredObject, StorageError>> {
    this.store.set(input.key, { body: toBytes(input.body), contentType: input.contentType });
    return Ok({ key: input.key, link: this.getLink(input.key) });
  }

  getLink(key: string): string {
    return `${this.baseUrl.replace(/\/+$/, '')}/${encodeKey(key)}`;
  }

  getSignedUrl(key: string, options: SignedUrlOptions = {}): string {
    const expiresIn = options.expiresIn ?? 900;
    const method = options.method ?? 'GET';
    return `${this.getLink(key)}?X-Sig=memory&X-Method=${method}&X-Expires=${expiresIn}`;
  }

  // ── test affordances ──
  /** Whether an object was saved under `key`. */
  has(key: string): boolean {
    return this.store.has(key);
  }

  /** The stored blob for `key`, or `undefined`. */
  read(key: string): StoredBlob | undefined {
    return this.store.get(key);
  }

  /** Number of stored objects. */
  get size(): number {
    return this.store.size;
  }

  /** Drop all stored objects. */
  clear(): void {
    this.store.clear();
  }
}

// ─── Testcontainers preset glue ──────────────────────────────────────────────────
// Per-preset start helpers that boot a real container AND emit a keyed config block
// valid against the matching preset schema (UPPERCASE key). A consumer int test is
// then just: `const { block } = await startPostgres(); registerStandardConfigs(...)`.

// `testcontainers` is an OPTIONAL peer dependency — imported lazily so importing
// this module (e.g. for `InMemoryBlockStorage`) never requires it. Only the
// container start helpers pull it in, on first use.
let testcontainersModule: typeof import('testcontainers') | undefined;
const loadTestcontainers = async (): Promise<typeof import('testcontainers')> =>
  (testcontainersModule ??= await import('testcontainers'));

/** A started preset container plus its schema-valid, keyed config block. */
export interface StartedPreset<E> {
  /** The underlying Testcontainer. */
  container: StartedTestContainer;
  /** The UPPERCASE connection key the block is registered under. */
  key: string;
  /** The single resolved entry. */
  entry: E;
  /** The keyed block `{ [KEY]: entry }`, valid against the preset schema. */
  block: Record<string, E>;
  /** Stop the container. */
  stop(): Promise<void>;
}

const started = <E>(key: string, entry: E, container: StartedTestContainer): StartedPreset<E> => ({
  container,
  key,
  entry,
  block: { [key]: entry },
  stop: () => container.stop().then(() => undefined),
});

/** Options common to every start helper. */
export interface StartOptions {
  /** UPPERCASE connection key (default `MAIN`). */
  key?: string;
  /** Override the container image. */
  image?: string;
}

export interface StartPostgresOptions extends StartOptions {
  database?: string;
  username?: string;
  password?: string;
}

/** Boot a Postgres container and emit a valid `postgres` block. */
export const startPostgres = async (options: StartPostgresOptions = {}): Promise<StartedPreset<PostgresEntry>> => {
  const key = options.key ?? 'MAIN';
  const database = options.database ?? 'app';
  const username = options.username ?? 'app';
  const password = options.password ?? 'app-secret';
  const { GenericContainer, Wait } = await loadTestcontainers();
  const container = await new GenericContainer(options.image ?? 'postgres:16-alpine')
    .withExposedPorts(5432)
    .withEnvironment({ POSTGRES_DB: database, POSTGRES_USER: username, POSTGRES_PASSWORD: password })
    .withWaitStrategy(Wait.forLogMessage(/database system is ready to accept connections/, 2))
    .start();
  return started<PostgresEntry>(
    key,
    {
      host: container.getHost(),
      port: container.getMappedPort(5432),
      database,
      username,
      password,
      ssl: false,
      pool: { min: 0, max: 10 },
    },
    container,
  );
};

export interface StartRedisOptions extends StartOptions {
  password?: string;
  db?: number;
}

const startRedis = async (
  defaultKey: string,
  options: StartRedisOptions,
): Promise<StartedPreset<RedisConnectionEntry>> => {
  const key = options.key ?? defaultKey;
  const password = options.password ?? '';
  const db = options.db ?? 0;
  const { GenericContainer, Wait } = await loadTestcontainers();
  const container = await new GenericContainer(options.image ?? 'redis:7-alpine')
    .withExposedPorts(6379)
    .withWaitStrategy(Wait.forLogMessage(/Ready to accept connections/))
    .start();
  return started<RedisConnectionEntry>(
    key,
    {
      host: container.getHost(),
      port: container.getMappedPort(6379),
      password,
      db,
      tls: false,
    },
    container,
  );
};

/** Boot a Redis-protocol container and emit a valid `cache` block (ephemeral). */
export const startCache = (options: StartRedisOptions = {}): Promise<StartedPreset<RedisConnectionEntry>> =>
  startRedis('MAIN', options);

/** Boot a Redis-protocol container and emit a valid `kv` block (persistent-role). */
export const startKv = (options: StartRedisOptions = {}): Promise<StartedPreset<RedisConnectionEntry>> =>
  startRedis('MAIN', options);

export interface StartStorageOptions extends StartOptions {
  bucket?: string;
  region?: string;
  accessKeyId?: string;
  secretAccessKey?: string;
}

const sha256hex = (data: string): string => createHash('sha256').update(data).digest('hex');
const hmac = (key: Buffer | string, data: string): Buffer => createHmac('sha256', key).update(data).digest();

/**
 * Create an S3 bucket with a hand-rolled SigV4-signed `PUT /{bucket}`. The
 * official `minio/minio` image does not auto-create buckets and Bun's S3 client
 * has no bucket API, so the glue signs the request itself (Node crypto, no extra
 * dependency). Exported so a consumer int test can create extra buckets against
 * a started endpoint. Throws on a non-2xx response.
 */
export const createS3Bucket = async (
  endpoint: string,
  region: string,
  accessKeyId: string,
  secretAccessKey: string,
  bucket: string,
): Promise<void> => {
  const host = new URL(endpoint).host;
  const amzDate = new Date().toISOString().replace(/[:-]|\.\d{3}/g, '');
  const date = amzDate.slice(0, 8);
  const payloadHash = sha256hex('');
  const canonicalHeaders = `host:${host}\nx-amz-content-sha256:${payloadHash}\nx-amz-date:${amzDate}\n`;
  const signedHeaders = 'host;x-amz-content-sha256;x-amz-date';
  const canonicalRequest = ['PUT', `/${bucket}`, '', canonicalHeaders, signedHeaders, payloadHash].join('\n');
  const scope = `${date}/${region}/s3/aws4_request`;
  const stringToSign = ['AWS4-HMAC-SHA256', amzDate, scope, sha256hex(canonicalRequest)].join('\n');
  const signingKey = hmac(hmac(hmac(hmac(`AWS4${secretAccessKey}`, date), region), 's3'), 'aws4_request');
  const signature = createHmac('sha256', signingKey).update(stringToSign).digest('hex');
  const authorization = `AWS4-HMAC-SHA256 Credential=${accessKeyId}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;
  const response = await fetch(`${endpoint.replace(/\/+$/, '')}/${bucket}`, {
    method: 'PUT',
    headers: { host, 'x-amz-date': amzDate, 'x-amz-content-sha256': payloadHash, authorization },
  });
  if (!response.ok) {
    throw new Error(`failed to create bucket "${bucket}": HTTP ${response.status}`);
  }
};

/**
 * Boot a MinIO container (S3-compatible) and emit a valid `storage` block. The
 * bucket is created after start via a signed request (see {@link createBucket}).
 */
export const startStorage = async (options: StartStorageOptions = {}): Promise<StartedPreset<StorageEntry>> => {
  const key = options.key ?? 'MAIN';
  const bucket = options.bucket ?? 'app';
  const region = options.region ?? 'us-east-1';
  const accessKeyId = options.accessKeyId ?? 'minioadmin';
  const secretAccessKey = options.secretAccessKey ?? 'minioadmin';
  const { GenericContainer, Wait } = await loadTestcontainers();
  const container = await new GenericContainer(options.image ?? 'minio/minio:latest')
    .withExposedPorts(9000)
    .withEnvironment({ MINIO_ROOT_USER: accessKeyId, MINIO_ROOT_PASSWORD: secretAccessKey })
    .withCommand(['server', '/data'])
    .withWaitStrategy(Wait.forLogMessage(/API:/i))
    .start();
  const endpoint = `http://${container.getHost()}:${container.getMappedPort(9000)}`;
  await createS3Bucket(endpoint, region, accessKeyId, secretAccessKey, bucket);
  return started<StorageEntry>(
    key,
    { endpoint, region, bucket, accessKeyId, secretAccessKey, forcePathStyle: true },
    container,
  );
};
