import { describe, expect, test } from 'bun:test';
import { Ok } from '@atomicloud/diene.result';
import { MercuryMaintenanceLoopJob, RuntimeStoreGenerationTarget } from '../../../src/composition/runtime.ts';
import type { LandscapeRuntimeConfig } from '../../../src/domain/index.ts';
import { ManualClock } from '../../../src/runtime/index.ts';
import { MemoryLandscapeStore } from '../../../src/storage/index.ts';

const config = (generation: number): LandscapeRuntimeConfig => ({
  generation,
  landscape: 'lapras',
  compiledAtMs: generation,
  sourceRevision: `revision-${generation}`,
  tenants: [],
});

describe('runtime composition', () => {
  test('stages, atomically flips, retains, and expires compiler generations', async () => {
    const store = new MemoryLandscapeStore('lapras', new ManualClock(0));
    const target = new RuntimeStoreGenerationTarget('lapras', store);
    await target.stageComplete(config(1));
    expect(await target.compareAndSwapActive(1, null)).toBe(true);

    await target.stageComplete(config(2));
    expect(await target.compareAndSwapActive(2, 1)).toBe(true);
    await target.requestRetention(1, new Date(2_000));
    expect(await (await store.discardExpired(1_999)).unwrap()).toEqual([]);
    expect(await (await store.discardExpired(2_000)).unwrap()).toEqual([1]);
    expect((await target.readActive())?.generation).toBe(2);
  });

  test('reports a concurrent active-pointer change without replacing it', async () => {
    const store = new MemoryLandscapeStore('lapras', new ManualClock(0));
    const target = new RuntimeStoreGenerationTarget('lapras', store);
    await target.stageComplete(config(1));
    expect(await target.compareAndSwapActive(1, null)).toBe(true);
    await target.stageComplete(config(2));

    expect(await target.compareAndSwapActive(2, null)).toBe(false);
    expect((await target.readActive())?.generation).toBe(1);
  });

  test('runs archive maintenance before removing expired config generations', async () => {
    const store = new MemoryLandscapeStore('lapras', new ManualClock(100));
    await (await store.stage(config(1))).unwrap();
    await (await store.activate(1, null)).unwrap();
    await (await store.stage(config(2))).unwrap();
    await (await store.activate(2, 1)).unwrap();
    await (await store.retainGeneration(1, 100)).unwrap();
    let archives = 0;
    const job = new MercuryMaintenanceLoopJob(
      {
        name: 'retention',
        run: async () => {
          archives += 1;
          return Ok(undefined);
        },
      },
      store,
      new ManualClock(100),
    );

    expect(await (await job.run(new AbortController().signal)).isOk()).toBe(true);
    expect(archives).toBe(1);
    expect(store.configGenerations.has(1)).toBe(false);
  });
});
