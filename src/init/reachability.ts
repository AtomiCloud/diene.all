import type { PostgresAdapter } from '../adapters/postgres';
import type { RedisAdapter } from '../adapters/redis';
import type { StorageAdapter } from '../adapters/storage';
import type { BucketProvisioner } from './bucket';
import { requireResult } from './result';

export class ReachabilityChecks {
  constructor(
    readonly postgres: readonly PostgresAdapter[],
    readonly redis: readonly RedisAdapter[],
    readonly storage: readonly StorageAdapter[],
    readonly bucketProvisioner: BucketProvisioner,
    readonly createBucket: boolean,
  ) {}

  async run(): Promise<void> {
    for (const adapter of this.postgres) await requireResult(adapter.ping());
    for (const adapter of this.redis) await requireResult(adapter.ping());
    for (const adapter of this.storage) {
      if (this.createBucket) await this.bucketProvisioner.ensure(adapter.entry);
      await requireResult(adapter.list());
    }
  }
}
