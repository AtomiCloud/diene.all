import { Err, Ok, Res, type Result } from '@atomicloud/diene.e2e/result';
import {
  S3BlockStorage,
  type BlockStorage,
  type SaveInput,
  type StorageBlock,
  type StorageEntry,
  type StoredObject,
} from '@atomicloud/diene.e2e/standard-config';
import { toS3Options } from '../lib/connection-options';
import { AdapterError } from './error';
import { type ApplicationTracer, withAdapterSpan } from './tracing';

export class StorageAdapter {
  constructor(
    readonly entry: StorageEntry,
    readonly tracer: ApplicationTracer,
    readonly name: string,
    readonly storage: BlockStorage = new S3BlockStorage(entry),
    readonly client: Bun.S3Client = new Bun.S3Client(toS3Options(entry)),
  ) {}

  list(): Result<number, AdapterError> {
    return Res.async(async () => {
      try {
        const response = await withAdapterSpan(
          this.tracer,
          'storage.s3.list',
          { 'atomi.adapter': 'storage', 'atomi.connection.name': this.name, 'server.address': this.entry.endpoint },
          () => this.client.list({ maxKeys: 1 }),
        );
        return Ok(response.keyCount ?? response.contents?.length ?? 0);
      } catch (error) {
        return Err(new AdapterError('storage.list', 'storage reachability check failed', error));
      }
    });
  }

  save(input: SaveInput): Result<StoredObject, AdapterError> {
    return Res.async(async () => {
      try {
        return await withAdapterSpan(
          this.tracer,
          'storage.s3.save',
          { 'atomi.adapter': 'storage', 'atomi.connection.name': this.name, 'server.address': this.entry.endpoint },
          async () =>
            (await this.storage.save(input)).match({
              err: error =>
                Err<StoredObject, AdapterError>(new AdapterError('storage.save', 'storage upload failed', error)),
              ok: value => Ok<StoredObject, AdapterError>(value),
            }),
        );
      } catch (error) {
        return Err(new AdapterError('storage.save', 'storage upload failed', error));
      }
    });
  }

  getLink(key: string): string {
    return this.storage.getLink(key);
  }

  getSignedUrl(key: string, expiresIn = 900): string {
    return this.storage.getSignedUrl(key, { expiresIn, method: 'GET' });
  }
}

export function buildStorageAdapters(
  block: StorageBlock,
  tracer: ApplicationTracer,
): ReadonlyMap<string, StorageAdapter> {
  return new Map(
    Object.entries(block).map(([name, entry]) => [name, new StorageAdapter(entry, tracer, name)] as const),
  );
}
