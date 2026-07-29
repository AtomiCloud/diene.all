import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type {
  Clock,
  RuntimeConfigReader,
  RuntimeJobFailure,
  RuntimeTelemetry,
  StorageFailure,
} from '../domain/index.ts';
import type { DeliveryEngine } from '../delivery/index.ts';
import type { EventRetentionManager } from '../storage/index.ts';

export type RuntimeLoopName = 'delivery' | 'retention';

export interface RuntimeLoopJob {
  readonly name: RuntimeLoopName;
  run(signal: AbortSignal): Promise<Result<void, RuntimeJobFailure>>;
}

export interface RuntimeLoopSpec {
  readonly job: RuntimeLoopJob;
  readonly intervalMs: number;
  readonly initialDelayMs?: number;
}

export interface RuntimeSleeper {
  sleep(milliseconds: number, signal: AbortSignal): Promise<void>;
}

export interface RetentionTenantSource {
  listTenantIds(): Promise<Result<readonly string[], StorageFailure>>;
}

class AbortableRuntimeSleeper implements RuntimeSleeper {
  async sleep(milliseconds: number, signal: AbortSignal): Promise<void> {
    if (signal.aborted || milliseconds <= 0) {
      return;
    }
    await new Promise<void>(resolve => {
      const done = (): void => {
        clearTimeout(timeout);
        signal.removeEventListener('abort', done);
        resolve();
      };
      const timeout = setTimeout(done, milliseconds);
      signal.addEventListener('abort', done, { once: true });
    });
  }
}

export class RuntimeConfigTenantSource implements RetentionTenantSource {
  constructor(readonly config: RuntimeConfigReader) {}

  async listTenantIds(): Promise<Result<readonly string[], StorageFailure>> {
    const active = await this.config.readActive();
    if (await active.isErr()) {
      return Err(await active.unwrapErr());
    }
    const snapshot = await active.unwrap();
    return Ok(snapshot === null ? [] : [...new Set(snapshot.tenants.map(tenant => tenant.id))]);
  }
}

export class DueDeliveryLoopJob implements RuntimeLoopJob {
  readonly name = 'delivery' as const;

  constructor(
    readonly engine: DeliveryEngine,
    readonly clock: Clock,
    readonly limit = 100,
  ) {}

  async run(signal: AbortSignal): Promise<Result<void, RuntimeJobFailure>> {
    if (signal.aborted) {
      return Ok(undefined);
    }
    const outcomes = await this.engine.runDue(this.clock.nowMs(), this.limit, signal);
    let failures = 0;
    for (const outcome of outcomes) {
      if (await outcome.isErr()) {
        failures += 1;
      }
    }
    return failures === 0
      ? Ok(undefined)
      : Err({
          code: 'delivery-failed',
          message: `${failures} due delivery job${failures === 1 ? '' : 's'} failed`,
          retryable: true,
        });
  }
}

export class ArchiveRetentionLoopJob implements RuntimeLoopJob {
  readonly name = 'retention' as const;

  constructor(
    readonly retention: EventRetentionManager,
    readonly tenants: RetentionTenantSource,
  ) {}

  async run(signal: AbortSignal): Promise<Result<void, RuntimeJobFailure>> {
    if (signal.aborted) {
      return Ok(undefined);
    }
    const tenantIds = await this.tenants.listTenantIds();
    if (await tenantIds.isErr()) {
      return Err({
        code: 'storage-unavailable',
        message: (await tenantIds.unwrapErr()).message,
        retryable: true,
      });
    }

    let failures = 0;
    for (const tenantId of await tenantIds.unwrap()) {
      if (signal.aborted) {
        break;
      }
      const result = await this.retention.rollover(tenantId);
      if (await result.isErr()) {
        failures += 1;
      }
    }
    return failures === 0
      ? Ok(undefined)
      : Err({
          code: 'retention-failed',
          message: `${failures} tenant retention job${failures === 1 ? '' : 's'} failed`,
          retryable: true,
        });
  }
}

/** Runs exactly one cancellable loop for delivery and one for retention. */
export class MercuryRuntimeSupervisor {
  private controller: AbortController | undefined;
  private activeRun: Promise<void> | undefined;

  constructor(
    readonly landscape: string,
    readonly delivery: RuntimeLoopSpec,
    readonly retention: RuntimeLoopSpec,
    readonly telemetry: RuntimeTelemetry,
    readonly sleeper: RuntimeSleeper = new AbortableRuntimeSleeper(),
  ) {
    if (delivery.job.name !== 'delivery' || retention.job.name !== 'retention') {
      throw new TypeError('delivery and retention loop jobs must use their matching names');
    }
    for (const loop of [delivery, retention]) {
      if (!Number.isSafeInteger(loop.intervalMs) || loop.intervalMs < 1) {
        throw new RangeError('runtime loop intervals must be positive integer milliseconds');
      }
      if (
        loop.initialDelayMs !== undefined &&
        (!Number.isSafeInteger(loop.initialDelayMs) || loop.initialDelayMs < 0)
      ) {
        throw new RangeError('runtime loop initial delays must be non-negative integer milliseconds');
      }
    }
  }

  get running(): boolean {
    return this.activeRun !== undefined;
  }

  start(): boolean {
    if (this.activeRun !== undefined) {
      return false;
    }
    const controller = new AbortController();
    this.controller = controller;
    const activeRun = Promise.all([
      this.runLoop(this.delivery, controller.signal),
      this.runLoop(this.retention, controller.signal),
    ]).then(
      () => undefined,
      async () => this.recordFailure('delivery', 'unexpected', true),
    );
    this.activeRun = activeRun;
    void activeRun.then(() => {
      if (this.activeRun === activeRun) {
        this.activeRun = undefined;
        this.controller = undefined;
      }
    });
    return true;
  }

  stop(): boolean {
    if (this.controller === undefined || this.controller.signal.aborted) {
      return false;
    }
    this.controller.abort();
    return true;
  }

  async drain(): Promise<void> {
    this.stop();
    await this.activeRun;
  }

  private async runLoop(loop: RuntimeLoopSpec, signal: AbortSignal): Promise<void> {
    if ((loop.initialDelayMs ?? 0) > 0) {
      if (!(await this.sleep(loop.job.name, loop.initialDelayMs ?? 0, signal))) {
        return;
      }
    }
    while (!signal.aborted) {
      await this.runTick(loop.job, signal);
      if (!signal.aborted && !(await this.sleep(loop.job.name, loop.intervalMs, signal))) {
        return;
      }
    }
  }

  private async runTick(job: RuntimeLoopJob, signal: AbortSignal): Promise<void> {
    try {
      const result = await job.run(signal);
      if (await result.isErr()) {
        const jobFailure = await result.unwrapErr();
        if (jobFailure.code !== 'cancelled') {
          await this.recordFailure(job.name, jobFailure.code, jobFailure.retryable);
        }
      }
    } catch {
      await this.recordFailure(job.name, 'unexpected', true);
    }
  }

  private async sleep(job: RuntimeLoopName, milliseconds: number, signal: AbortSignal): Promise<boolean> {
    try {
      await this.sleeper.sleep(milliseconds, signal);
      return true;
    } catch {
      await this.recordFailure(job, 'unexpected', true);
      return false;
    }
  }

  private async recordFailure(job: RuntimeLoopName, code: string, retryable: boolean): Promise<void> {
    try {
      await this.telemetry.record({
        name: 'runtime.job.failure',
        attributes: { code, job, landscape: this.landscape, retryable },
      });
    } catch {
      // Telemetry must never terminate the runtime loops.
    }
  }
}
