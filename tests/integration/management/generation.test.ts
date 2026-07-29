import { describe, expect, test } from 'bun:test';
import { InMemoryLandscapeConfigWriter, MercuryConfigurationCompiler } from '../../../src/management/compiler.ts';
import { InMemoryManagementRepository } from '../../../src/management/memory-repository.ts';
import { ManagementService } from '../../../src/management/service.ts';
import type { LandscapeTopology } from '../../../src/management/types.ts';

describe('management configuration generations', () => {
  test('keeps independent A then B then A generation chains in one shared repository', async () => {
    let clock = new Date('2026-07-29T00:00:00.000Z');
    let id = 0;
    const repository = new InMemoryManagementRepository();
    const service = new ManagementService(repository, {
      clock: () => new Date(clock),
      idFactory: () => `00000000-0000-4000-8000-${(++id).toString().padStart(12, '0')}`,
    });
    const { account } = await service.provisionDefaultInternalAccount('boot');
    await service.createOrAdoptTenant({
      accountId: account.id,
      name: 'internal/nitroso',
      intakeSlug: 'nitroso',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    const writerA = new InMemoryLandscapeConfigWriter();
    const compilerA = new MercuryConfigurationCompiler(repository, writerA, {
      clock: () => new Date(clock),
      graceSeconds: 60,
    });
    const writerB = new InMemoryLandscapeConfigWriter();
    const compilerB = new MercuryConfigurationCompiler(repository, writerB, {
      clock: () => new Date(clock),
      graceSeconds: 60,
    });
    const topologyA: LandscapeTopology = {
      landscapes: ['raichu'],
      services: {},
    };
    const topologyB: LandscapeTopology = {
      landscapes: ['ampharos'],
      services: {},
    };

    const firstA = await compilerA.compileAndPublish(topologyA);
    clock = new Date('2026-07-29T00:00:30.000Z');
    const firstB = await compilerB.compileAndPublish(topologyB);
    clock = new Date('2026-07-29T00:01:00.000Z');
    const secondA = await compilerA.compileAndPublish(topologyA);

    expect([firstA.generation.generation, firstB.generation.generation, secondA.generation.generation]).toEqual([
      1, 2, 3,
    ]);
    expect(writerA.currentGeneration('raichu')).toBe(secondA.generation.generation);
    expect(writerB.currentGeneration('ampharos')).toBe(firstB.generation.generation);
    expect(await repository.getActiveConfigGeneration('raichu')).toEqual(secondA.generation);
    expect(await repository.getActiveConfigGeneration('ampharos')).toEqual(firstB.generation);

    expect(await repository.getConfigGeneration(firstA.generation.generation)).toMatchObject({
      landscape: 'raichu',
      status: 'superseded',
    });
    expect(firstB.generation).toMatchObject({
      landscape: 'ampharos',
      status: 'active',
      previousGeneration: undefined,
    });
    expect(secondA.generation).toMatchObject({
      landscape: 'raichu',
      status: 'active',
      previousGeneration: firstA.generation.generation,
    });

    expect(writerA.retainedUntil('raichu', firstA.generation.generation)).toEqual(new Date('2026-07-29T00:02:00.000Z'));
    expect(writerA.retainedUntil('raichu', firstB.generation.generation)).toBeUndefined();
    expect(writerB.retainedUntil('ampharos', firstA.generation.generation)).toBeUndefined();
    expect(writerB.retainedUntil('ampharos', firstB.generation.generation)).toBeUndefined();
    expect(await repository.listLandscapeAcknowledgements(secondA.generation.generation)).toHaveLength(1);
    expect(await repository.listLandscapeAcknowledgements(firstB.generation.generation)).toHaveLength(1);
  });
});
