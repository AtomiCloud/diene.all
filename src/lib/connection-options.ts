import type { PostgresEntry, RedisConnectionEntry, StorageEntry } from '@atomicloud/diene.e2e/standard-config';

export interface PostgresConnectionOptions {
  readonly database: string;
  readonly host: string;
  readonly max: number;
  readonly min: number;
  readonly password: string;
  readonly port: number;
  readonly ssl: false | 'require';
  readonly username: string;
}

export interface RedisConnectionOptions {
  readonly db: number;
  readonly host: string;
  readonly lazyConnect: true;
  readonly password?: string;
  readonly port: number;
  readonly tls?: Record<string, never>;
}

export interface S3ConnectionOptions {
  readonly accessKeyId: string;
  readonly bucket: string;
  readonly endpoint: string;
  readonly region: string;
  readonly secretAccessKey: string;
  readonly virtualHostedStyle: boolean;
}

export function toPostgresOptions(entry: PostgresEntry): PostgresConnectionOptions {
  return {
    database: entry.database,
    host: entry.host,
    max: entry.pool.max,
    min: entry.pool.min,
    password: entry.password,
    port: entry.port,
    ssl: entry.ssl ? 'require' : false,
    username: entry.username,
  };
}

export function toRedisOptions(entry: RedisConnectionEntry): RedisConnectionOptions {
  return {
    db: entry.db,
    host: entry.host,
    lazyConnect: true,
    password: entry.password.length > 0 ? entry.password : undefined,
    port: entry.port,
    tls: entry.tls ? {} : undefined,
  };
}

export function toS3Options(entry: StorageEntry): S3ConnectionOptions {
  return {
    accessKeyId: entry.accessKeyId,
    bucket: entry.bucket,
    endpoint: entry.endpoint,
    region: entry.region,
    secretAccessKey: entry.secretAccessKey,
    virtualHostedStyle: !entry.forcePathStyle,
  };
}
