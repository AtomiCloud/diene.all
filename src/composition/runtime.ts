import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type { Clock, LandscapeRuntimeConfig, RuntimeConfigStore, RuntimeJobFailure } from '../domain/index.ts';
import type { RuntimeGenerationTarget } from '../management/index.ts';
import type { RuntimeLoopJob } from '../runtime/index.ts';

const storageError = async <Value>(
  result:
    | Result<Value, { readonly code: string; readonly message: string }>
    | Promise<Result<Value, { readonly code: string; readonly message: string }>>,
  operation: string,
): Promise<Value> => {
  const resolved = await result;
  if (await resolved.isErr()) {
    const failure = await resolved.unwrapErr();
    throw new Error(`${operation} failed: ${failure.code}`);
  }
  return resolved.unwrap();
};

/** Adapts the landscape-local runtime store to Mercury's Neon compiler seam. */
export class RuntimeStoreGenerationTarget implements RuntimeGenerationTarget {
  constructor(
    readonly landscape: string,
    readonly store: RuntimeConfigStore,
  ) {}

  readActive(): Promise<LandscapeRuntimeConfig | null> {
    return storageError(this.store.readActive(), 'read active generation');
  }

  async stageComplete(config: LandscapeRuntimeConfig): Promise<void> {
    if (config.landscape !== this.landscape) {
      throw new Error(`runtime generation belongs to ${config.landscape}, not ${this.landscape}`);
    }
    await storageError(this.store.stage(config), 'stage generation');
  }

  async compareAndSwapActive(generation: number, expectedPreviousGeneration: number | null): Promise<boolean> {
    const result = await this.store.activate(generation, expectedPreviousGeneration);
    if (await result.isErr()) {
      const failure = await result.unwrapErr();
      if (failure.code === 'conflict') {
        return false;
      }
      throw new Error(`activate generation failed: ${failure.code}`);
    }
    return true;
  }

  async requestRetention(generation: number, until: Date): Promise<void> {
    await storageError(this.store.retainGeneration(generation, until.getTime()), 'retain generation');
  }
}

/** Adds expired config-generation cleanup to the ordinary archive loop. */
export class MercuryMaintenanceLoopJob implements RuntimeLoopJob {
  readonly name = 'retention' as const;

  constructor(
    readonly archive: RuntimeLoopJob,
    readonly config: RuntimeConfigStore,
    readonly clock: Clock,
  ) {
    if (archive.name !== 'retention') {
      throw new TypeError('maintenance archive job must be a retention loop');
    }
  }

  async run(signal: AbortSignal): Promise<Result<void, RuntimeJobFailure>> {
    const archived = await this.archive.run(signal);
    if (signal.aborted) {
      return archived;
    }
    const discarded = await this.config.discardExpired(this.clock.nowMs());
    if (await discarded.isErr()) {
      return Err({
        code: 'storage-unavailable',
        message: 'expired runtime configuration cleanup failed',
        retryable: true,
      });
    }
    return (await archived.isErr()) ? Err(await archived.unwrapErr()) : Ok(undefined);
  }
}
