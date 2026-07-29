import { describe, it } from 'bun:test';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import should from 'should';
import type { RuntimeJobFailure } from '../../../src/domain/index.ts';
import { MemoryTelemetry } from '../../../src/runtime/fakes.ts';
import {
  MercuryRuntimeSupervisor,
  type RuntimeLoopJob,
  type RuntimeLoopName,
  type RuntimeSleeper,
} from '../../../src/runtime/supervisor.ts';

const flush = async (): Promise<void> => {
  await new Promise(resolve => setTimeout(resolve, 0));
};

class ManualSleeper implements RuntimeSleeper {
  readonly waits: Array<{ milliseconds: number; finish: () => void }> = [];

  async sleep(milliseconds: number, signal: AbortSignal): Promise<void> {
    if (signal.aborted) {
      return;
    }
    await new Promise<void>(resolve => {
      const finish = (): void => {
        signal.removeEventListener('abort', finish);
        const index = this.waits.findIndex(wait => wait.finish === finish);
        if (index >= 0) {
          this.waits.splice(index, 1);
        }
        resolve();
      };
      this.waits.push({ milliseconds, finish });
      signal.addEventListener('abort', finish, { once: true });
    });
  }

  advance(milliseconds: number): void {
    const wait = this.waits.find(candidate => candidate.milliseconds === milliseconds);
    if (wait === undefined) {
      throw new Error(`no ${milliseconds}ms runtime wait is pending`);
    }
    wait.finish();
  }
}

class BlockingJob implements RuntimeLoopJob {
  public calls = 0;
  public active = 0;
  public maximumActive = 0;
  public observedAbort = false;
  readonly releases: Array<() => void> = [];

  constructor(readonly name: RuntimeLoopName) {}

  async run(signal: AbortSignal): Promise<Result<void, RuntimeJobFailure>> {
    this.calls += 1;
    this.active += 1;
    this.maximumActive = Math.max(this.maximumActive, this.active);
    return new Promise(resolve => {
      const finish = (): void => {
        signal.removeEventListener('abort', abort);
        this.active -= 1;
        resolve(Ok(undefined));
      };
      const abort = (): void => {
        this.observedAbort = true;
        finish();
      };
      this.releases.push(finish);
      signal.addEventListener('abort', abort, { once: true });
    });
  }

  release(): void {
    const release = this.releases.shift();
    if (release === undefined) {
      throw new Error('no runtime job tick is pending');
    }
    release();
  }
}

class SequenceJob implements RuntimeLoopJob {
  public calls = 0;

  constructor(
    readonly name: RuntimeLoopName,
    readonly results: Result<void, RuntimeJobFailure>[],
  ) {}

  async run(): Promise<Result<void, RuntimeJobFailure>> {
    this.calls += 1;
    return this.results.shift() ?? Ok(undefined);
  }
}

describe('MercuryRuntimeSupervisor', () => {
  it('should start idempotently, never overlap a loop tick, and drain in-flight work after cancellation', async () => {
    // Arrange
    const delivery = new BlockingJob('delivery');
    const retention = new BlockingJob('retention');
    const sleeper = new ManualSleeper();
    const subject = new MercuryRuntimeSupervisor(
      'raichu',
      { job: delivery, intervalMs: 10 },
      { job: retention, intervalMs: 20 },
      new MemoryTelemetry(),
      sleeper,
    );

    // Act
    const firstStart = subject.start();
    const duplicateStart = subject.start();
    await flush();
    delivery.release();
    await flush();
    sleeper.advance(10);
    await flush();
    await subject.drain();

    // Assert
    should(firstStart).be.true();
    should(duplicateStart).be.false();
    should(delivery.calls).equal(2);
    should(delivery.maximumActive).equal(1);
    should(retention.calls).equal(1);
    should(delivery.observedAbort).be.true();
    should(retention.observedAbort).be.true();
    should(subject.running).be.false();
  });

  it('should emit typed failure telemetry and continue the same loop on its next interval', async () => {
    // Arrange
    const delivery = new SequenceJob('delivery', [
      Err({
        code: 'delivery-failed',
        message: 'sensitive adapter detail',
        retryable: true,
      }),
      Ok(undefined),
    ]);
    const retention = new SequenceJob('retention', [Ok(undefined)]);
    const sleeper = new ManualSleeper();
    const telemetry = new MemoryTelemetry();
    const subject = new MercuryRuntimeSupervisor(
      'raichu',
      { job: delivery, intervalMs: 10 },
      { job: retention, intervalMs: 20 },
      telemetry,
      sleeper,
    );

    // Act
    subject.start();
    await flush();
    sleeper.advance(10);
    await flush();
    await subject.drain();

    // Assert
    should(delivery.calls).equal(2);
    should(telemetry.events).have.length(1);
    should(telemetry.events[0]?.name).equal('runtime.job.failure');
    should(telemetry.events[0]?.attributes).deepEqual({
      code: 'delivery-failed',
      job: 'delivery',
      landscape: 'raichu',
      retryable: true,
    });
    should(JSON.stringify(telemetry.events)).not.containEql('sensitive adapter detail');
  });
});
