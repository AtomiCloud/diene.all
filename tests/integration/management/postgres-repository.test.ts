import { afterAll, beforeAll, describe, expect, test } from 'bun:test';
import { fileURLToPath } from 'node:url';
import postgres, { type Sql } from 'postgres';
import { GenericContainer, type StartedTestContainer, Wait } from 'testcontainers';
import { runMercuryMigrations } from '../../../src/composition/migrations.ts';
import type { LandscapeRuntimeConfig } from '../../../src/domain/index.ts';
import { MercuryConfigurationCompiler } from '../../../src/management/compiler.ts';
import { PostgresManagementRepository } from '../../../src/management/postgres-repository.ts';
import {
  LocalLandscapeConfigWriter,
  type RuntimeGenerationTarget,
} from '../../../src/management/runtime-generation.ts';
import { ManagementService } from '../../../src/management/service.ts';
import type { LandscapeAcknowledgement, LandscapeTopology } from '../../../src/management/types.ts';
import { PostgresAppleBackfillStateStore } from '../../../src/provider-operations/postgres-apple-backfill-store.ts';

class PostgresTestRuntimeTarget implements RuntimeGenerationTarget {
  public active: LandscapeRuntimeConfig | null = null;
  readonly staged = new Map<number, LandscapeRuntimeConfig>();
  readonly retention = new Map<number, Date>();

  public constructor(public readonly landscape: string) {}

  public async readActive(): Promise<LandscapeRuntimeConfig | null> {
    return structuredClone(this.active);
  }

  public async stageComplete(config: LandscapeRuntimeConfig): Promise<void> {
    this.staged.set(config.generation, structuredClone(config));
  }

  public async compareAndSwapActive(generation: number, expectedPreviousGeneration: number | null): Promise<boolean> {
    if ((this.active?.generation ?? null) !== expectedPreviousGeneration) {
      return false;
    }
    const staged = this.staged.get(generation);
    if (staged === undefined) {
      return false;
    }
    this.active = structuredClone(staged);
    return true;
  }

  public async requestRetention(generation: number, until: Date): Promise<void> {
    this.retention.set(generation, new Date(until));
  }
}

class FailOncePostgresAcknowledgementRepository extends PostgresManagementRepository {
  public failNextAcknowledgement = true;

  public override async saveLandscapeAcknowledgement(
    acknowledgement: LandscapeAcknowledgement,
  ): Promise<LandscapeAcknowledgement> {
    if (this.failNextAcknowledgement) {
      this.failNextAcknowledgement = false;
      throw new Error('simulated Neon acknowledgement outage');
    }
    return super.saveLandscapeAcknowledgement(acknowledgement);
  }
}

describe('Neon/Postgres management repository', () => {
  let container: StartedTestContainer;
  let sql: Sql;
  let repository: PostgresManagementRepository;

  beforeAll(async () => {
    container = await new GenericContainer('postgres:17-alpine')
      .withEnvironment({
        POSTGRES_DB: 'mercury',
        POSTGRES_PASSWORD: 'mercury',
        POSTGRES_USER: 'mercury',
      })
      .withExposedPorts(5432)
      .withWaitStrategy(Wait.forLogMessage(/database system is ready to accept connections/, 2))
      .start();
    sql = postgres({
      host: container.getHost(),
      port: container.getMappedPort(5432),
      database: 'mercury',
      username: 'mercury',
      password: 'mercury',
      max: 2,
    });
    const migrationDirectory = fileURLToPath(new URL('../../../migrations/', import.meta.url));
    const concurrentMigrations = await Promise.all([
      runMercuryMigrations(sql, migrationDirectory),
      runMercuryMigrations(sql, migrationDirectory),
    ]);
    expect(concurrentMigrations.every(migrations => migrations.length === 2)).toBe(true);
    expect(await runMercuryMigrations(sql, migrationDirectory)).toHaveLength(2);
    const applied = await sql<
      { count: number }[]
    >`SELECT count(*)::integer AS count FROM public.mercury_schema_migrations`;
    expect(applied[0]?.count).toBe(2);
    repository = new PostgresManagementRepository(sql);
  }, 120_000);

  afterAll(async () => {
    await sql?.end();
    await container?.stop();
  }, 120_000);

  test('round-trips seeded account, immutable tenant, quota, metering, and landscape generation truth', async () => {
    let id = 1;
    const service = new ManagementService(repository, {
      clock: () => new Date('2026-07-29T00:00:00.000Z'),
      idFactory: () => `00000000-0000-4000-8000-${(id++).toString().padStart(12, '0')}`,
    });
    const provisioned = await service.provisionDefaultInternalAccount('bootstrap-token');
    expect(provisioned.account.name).toBe('internal/default');
    expect(provisioned.issued?.token).toBe('bootstrap-token');
    const tenant = await service.createOrAdoptTenant({
      accountId: provisioned.account.id,
      name: 'internal/nitroso',
      intakeSlug: 'nitroso',
      source: 'cr',
      homeVlandscape: 'mew',
    });

    expect(await repository.findTenantByName('internal/nitroso')).toEqual(tenant);
    expect(await repository.getQuota(tenant.id)).toMatchObject({
      intakeRps: 50,
      retryWindowSeconds: 259_200,
    });
    expect(await repository.getMeteringConfiguration(tenant.id)).toMatchObject({
      enabled: true,
      dimensions: ['intake', 'delivery', 'replay', 'archive_bytes'],
    });
    await expect(repository.saveTenant({ ...tenant, homeVlandscape: 'ditto' })).rejects.toThrow(
      'tenant home_vlandscape and intake_slug are immutable',
    );
    await expect(repository.saveTenant({ ...tenant, intakeSlug: 'renamed' })).rejects.toThrow(
      'tenant home_vlandscape and intake_slug are immutable',
    );

    const principal = await service.authenticateBearer('Bearer bootstrap-token');
    expect(await repository.consumeManagementRate(principal.credentialId, 1_785_283_200, 1, 1)).toBe(true);
    expect(await repository.consumeManagementRate(principal.credentialId, 1_785_283_200, 1, 1)).toBe(false);
    const firstProviderCredential = await service.registerProviderCredential(principal, tenant.id, {
      provider: 'stripe',
      secretPointer: '/mew-stripe-v1',
    });
    const providerCredential = await service.registerProviderCredential(principal, tenant.id, {
      provider: 'stripe',
      secretPointer: '/mew-stripe-v2',
    });
    expect(await repository.getProviderCredential(firstProviderCredential.id)).toMatchObject({
      generation: 1,
      status: 'overlap',
      overlapUntil: new Date('2026-07-31T00:00:00.000Z'),
    });
    expect(providerCredential).toMatchObject({ generation: 2, status: 'live' });
    const route = await service.upsertRoute(principal, tenant.id, {
      path: '/webhook/stripe',
      registeredUrl: 'https://hooks.mercury.p.mew.cluster.atomi.cloud/t/nitroso/webhook/stripe',
      provider: 'stripe',
      providerCredentialId: providerCredential.id,
    });
    const firstSigningCredential = await service.registerEndpointSigningCredential(principal, tenant.id, {
      endpointId: '00000000-0000-4000-8000-000000000098',
      secretPointer: '/mew-signing-v1',
    });
    const signingCredential = await service.registerEndpointSigningCredential(principal, tenant.id, {
      endpointId: '00000000-0000-4000-8000-000000000098',
      secretPointer: '/mew-signing-v2',
    });
    expect(await repository.getEndpointSigningCredential(firstSigningCredential.id)).toMatchObject({
      generation: 1,
      status: 'overlap',
      overlapUntil: new Date('2026-07-31T00:00:00.000Z'),
    });
    expect(signingCredential).toMatchObject({ generation: 2, status: 'live' });
    await expect(
      repository.saveEndpointSigningCredential({
        id: '00000000-0000-4000-8000-000000000097',
        accountId: provisioned.account.id,
        tenantId: tenant.id,
        endpointId: '00000000-0000-4000-8000-000000000098',
        generation: 3,
        secretPointer: '/mew/signing-invalid',
        status: 'planned',
        createdAt: new Date('2026-07-29T00:00:00.000Z'),
      }),
    ).rejects.toThrow();
    const endpoint = await service.upsertEndpoint(principal, tenant.id, route.id, {
      id: '00000000-0000-4000-8000-000000000098',
      target: {
        kind: 'coordinate',
        service: 'zinc',
        module: 'checkout',
        canonicalVlandscape: 'mew',
      },
      signingCredentialId: signingCredential.id,
    });
    const targetA = new PostgresTestRuntimeTarget('raichu');
    const compilerA = new MercuryConfigurationCompiler(repository, new LocalLandscapeConfigWriter(targetA), {
      clock: () => new Date('2026-07-29T00:01:00.000Z'),
      graceSeconds: 60,
    });
    const topologyA: LandscapeTopology = {
      landscapes: ['raichu'],
      services: {
        'zinc/checkout': {
          module: 'checkout',
          localLandscapes: ['raichu'],
          canonicalVlandscape: 'mew',
          canonicalAddress: 'https://checkout.zinc.p.mew.cluster.atomi.cloud',
        },
      },
    };
    const targetB = new PostgresTestRuntimeTarget('ampharos');
    const compilerB = new MercuryConfigurationCompiler(repository, new LocalLandscapeConfigWriter(targetB), {
      clock: () => new Date('2026-07-29T00:01:30.000Z'),
      graceSeconds: 60,
    });
    const topologyB: LandscapeTopology = {
      landscapes: ['ampharos'],
      services: {
        'zinc/checkout': {
          module: 'checkout',
          localLandscapes: [],
          canonicalVlandscape: 'mew',
          canonicalAddress: 'https://checkout.zinc.p.mew.cluster.atomi.cloud',
        },
      },
    };
    const firstA = await compilerA.compileAndPublish(topologyA);
    const firstB = await compilerB.compileAndPublish(topologyB);
    const secondA = await compilerA.compileAndPublish(topologyA);

    expect(targetA.active?.generation).toBe(secondA.generation.generation);
    expect(targetB.active?.generation).toBe(firstB.generation.generation);
    expect(targetA.retention.has(firstA.generation.generation)).toBe(true);
    expect(targetA.retention.has(firstB.generation.generation)).toBe(false);
    expect(targetB.retention.size).toBe(0);
    expect(await repository.getActiveConfigGeneration('raichu')).toEqual(secondA.generation);
    expect(await repository.getActiveConfigGeneration('ampharos')).toEqual(firstB.generation);
    expect(secondA.generation.previousGeneration).toBe(firstA.generation.generation);
    expect(firstB.generation.previousGeneration).toBeUndefined();
    expect(await repository.listLandscapeAcknowledgements(secondA.generation.generation)).toHaveLength(1);

    let duplicateActiveRejected = false;
    try {
      await sql`
        INSERT INTO mercury_management.config_generations
          (generation, landscape, status, content_hash, created_at)
        VALUES
          (900000, 'raichu', 'active', 'duplicate-active', CURRENT_TIMESTAMP)
      `;
    } catch {
      duplicateActiveRejected = true;
    }
    expect(duplicateActiveRejected).toBe(true);

    let landscapeMutationError = '';
    try {
      await sql`
        UPDATE mercury_management.config_generations
        SET landscape = 'pikachu'
        WHERE generation = ${firstA.generation.generation}
      `;
    } catch (error) {
      landscapeMutationError = error instanceof Error ? error.message : String(error);
    }
    expect(landscapeMutationError).toContain('configuration generation landscape is immutable');

    const sibling = await service.createOrAdoptTenant({
      accountId: provisioned.account.id,
      name: 'internal/sibling',
      intakeSlug: 'sibling',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    const siblingProvider = await service.registerProviderCredential(principal, sibling.id, {
      provider: 'stripe',
      secretPointer: '/sibling-stripe',
    });
    let crossTenantProviderRejected = false;
    try {
      await repository.saveRoute({ ...route, providerCredentialId: siblingProvider.id });
    } catch {
      crossTenantProviderRejected = true;
    }
    expect(crossTenantProviderRejected).toBe(true);

    await repository.saveEndpointSigningCredential({
      id: '00000000-0000-4000-8000-000000000199',
      accountId: provisioned.account.id,
      tenantId: sibling.id,
      endpointId: endpoint.id,
      generation: 1,
      secretPointer: '/sibling-signing',
      status: 'live',
      createdAt: new Date('2026-07-29T00:00:00.000Z'),
    });
    let crossTenantSigningRejected = false;
    try {
      await repository.saveEndpoint({
        ...endpoint,
        signingCredentialId: '00000000-0000-4000-8000-000000000199',
      });
    } catch {
      crossTenantSigningRejected = true;
    }
    expect(crossTenantSigningRejected).toBe(true);

    await expect(service.deleteTenant(principal, tenant.id)).rejects.toMatchObject({ code: 'conflict' });
    const empty = await service.createOrAdoptTenant({
      accountId: provisioned.account.id,
      name: 'internal/empty-cleanup',
      intakeSlug: 'empty-cleanup',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    await service.deleteTenant(principal, empty.id);
    expect(await repository.getTenant(empty.id)).toBeUndefined();
    expect(await repository.getQuota(empty.id)).toBeUndefined();
    expect(await repository.getMeteringConfiguration(empty.id)).toBeUndefined();

    const recoveryRepository = new FailOncePostgresAcknowledgementRepository(sql);
    const recoveryTarget = new PostgresTestRuntimeTarget('pikachu');
    const recoveryCompiler = new MercuryConfigurationCompiler(
      recoveryRepository,
      new LocalLandscapeConfigWriter(recoveryTarget),
      { clock: () => new Date('2026-07-29T00:02:00.000Z') },
    );
    const recoveryTopology: LandscapeTopology = {
      landscapes: ['pikachu'],
      services: {
        'zinc/checkout': {
          module: 'checkout',
          localLandscapes: ['pikachu'],
          canonicalVlandscape: 'mew',
        },
      },
    };
    await expect(recoveryCompiler.compileAndPublish(recoveryTopology)).rejects.toMatchObject({
      code: 'compiler_failed',
    });
    const activatedGeneration = recoveryTarget.active?.generation;
    expect(activatedGeneration).toBeNumber();
    if (activatedGeneration === undefined) throw new Error('expected activated runtime generation');
    expect((await repository.getConfigGeneration(activatedGeneration))?.status).toBe('activated');
    const recoveredGeneration = await recoveryCompiler.compileAndPublish(recoveryTopology);
    expect(recoveredGeneration.generation.generation).toBeGreaterThan(activatedGeneration);
    expect((await repository.getConfigGeneration(activatedGeneration))?.status).toBe('superseded');

    const providerOperations = new PostgresAppleBackfillStateStore(sql);
    const acquired = await providerOperations.acquireLease({
      operationKey: 'apple-history',
      ownerId: 'mercury-primary',
      token: 'lease-token',
      nowMs: Date.parse('2026-07-29T00:00:00.000Z'),
      leaseDurationMs: 60_000,
    });
    expect(await acquired.isOk()).toBe(true);
    const lease = await acquired.unwrap();
    expect(lease).not.toBeNull();
    if (lease === null) {
      throw new Error('expected provider operation lease');
    }
    const advanced = await providerOperations.advanceCursor({
      lease,
      cursorAfter: 'cursor-1',
      nowMs: Date.parse('2026-07-29T00:00:01.000Z'),
    });
    expect(await advanced.unwrap()).toMatchObject({
      cursor: 'cursor-1',
      consecutiveMissedCycles: 0,
    });
    for (let cycle = 0; cycle < 3; cycle += 1) {
      await providerOperations.recordMissedCycle({
        lease,
        nowMs: Date.parse('2026-07-29T00:00:02.000Z') + cycle,
      });
    }
    const state = await providerOperations.readState('apple-history');
    expect(await state.unwrap()).toMatchObject({
      cursor: 'cursor-1',
      consecutiveMissedCycles: 3,
      alert: true,
    });
  }, 120_000);

  test('atomically rebinds a bound signing credential and rolls back every failed cutover boundary', async () => {
    let id = 800;
    const generatedIds: string[] = [];
    const service = new ManagementService(repository, {
      clock: () => new Date('2026-07-29T01:00:00.000Z'),
      idFactory: () => {
        const generated = `00000000-0000-4000-9000-${(id++).toString().padStart(12, '0')}`;
        generatedIds.push(generated);
        return generated;
      },
    });
    const account = await service.createAccount({ name: 'internal/atomic-signing-pg', kind: 'internal' });
    await service.issueManagementCredential(account.id, undefined, ['*'], 'atomic-signing-pg-token');
    const principal = await service.authenticateBearer('Bearer atomic-signing-pg-token');
    const tenant = await service.createOrAdoptTenant({
      accountId: account.id,
      name: 'internal/atomic-signing-pg',
      intakeSlug: 'atomic-signing-pg',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    const route = await service.upsertRoute(principal, tenant.id, {
      path: '/webhook/stripe',
      registeredUrl: 'https://hooks.mercury.p.mew.cluster.atomi.cloud/t/atomic-signing-pg/webhook/stripe',
      provider: 'stripe',
    });
    const endpointId = '00000000-0000-4000-9000-000000000098';
    const first = await service.registerEndpointSigningCredential(principal, tenant.id, {
      endpointId,
      secretPointer: '/atomic-pg-signing-v1',
    });
    await service.upsertEndpoint(principal, tenant.id, route.id, {
      id: endpointId,
      target: {
        kind: 'coordinate',
        service: 'zinc',
        module: 'checkout',
        canonicalVlandscape: 'mew',
      },
      signingCredentialId: first.id,
    });

    const target = new PostgresTestRuntimeTarget('atomic-signing-pg');
    const compiler = new MercuryConfigurationCompiler(repository, new LocalLandscapeConfigWriter(target), {
      clock: () => new Date('2026-07-29T01:01:00.000Z'),
      graceSeconds: 60,
    });
    const topology: LandscapeTopology = {
      landscapes: ['atomic-signing-pg'],
      services: {
        'zinc/checkout': {
          module: 'checkout',
          localLandscapes: ['atomic-signing-pg'],
          canonicalVlandscape: 'mew',
          canonicalAddress: 'https://checkout.zinc.p.mew.cluster.atomi.cloud',
        },
      },
    };
    const activeSigningRef = () =>
      target.active?.tenants
        .find(candidate => candidate.id === tenant.id)
        ?.routes.find(candidate => candidate.id === route.id)
        ?.endpoints.find(candidate => candidate.id === endpointId)?.signingSecretRef;
    let published = await compiler.compileAndPublish(topology);
    let previousGeneration = published.generation.generation;
    expect(activeSigningRef()).toBe('/atomic-pg-signing-v1');

    await sql`
      CREATE FUNCTION mercury_management.fail_atomic_signing_endpoint_rebind()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF OLD.id = '00000000-0000-4000-9000-000000000098'::uuid
           AND NEW.signing_credential_id IS DISTINCT FROM OLD.signing_credential_id THEN
          RAISE EXCEPTION 'injected endpoint rebind failure';
        END IF;
        RETURN NEW;
      END;
      $$
    `;
    await sql`
      CREATE TRIGGER fail_atomic_signing_endpoint_rebind
      BEFORE UPDATE OF signing_credential_id
      ON mercury_management.endpoints
      FOR EACH ROW EXECUTE FUNCTION mercury_management.fail_atomic_signing_endpoint_rebind()
    `;
    try {
      await expect(
        service.registerEndpointSigningCredential(principal, tenant.id, {
          endpointId,
          secretPointer: '/atomic-pg-signing-failed-rebind',
        }),
      ).rejects.toThrow('injected endpoint rebind failure');
    } finally {
      await sql`DROP TRIGGER fail_atomic_signing_endpoint_rebind ON mercury_management.endpoints`;
      await sql`DROP FUNCTION mercury_management.fail_atomic_signing_endpoint_rebind()`;
    }
    const failedRebindId = generatedIds.at(-1);
    expect(failedRebindId).toBeDefined();
    expect(await repository.getEndpointSigningCredential(failedRebindId as string)).toBeUndefined();
    expect(await repository.getEndpoint(endpointId)).toMatchObject({ signingCredentialId: first.id });
    expect(await repository.getEndpointSigningCredential(first.id)).toMatchObject({ status: 'live' });
    published = await compiler.compileAndPublish(topology);
    expect(published.generation.previousGeneration).toBe(previousGeneration);
    previousGeneration = published.generation.generation;
    expect(activeSigningRef()).toBe('/atomic-pg-signing-v1');

    await sql`
      CREATE FUNCTION mercury_management.fail_atomic_signing_overlap_transition()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF OLD.endpoint_id = '00000000-0000-4000-9000-000000000098'::uuid
           AND OLD.status = 'live'
           AND NEW.status = 'overlap' THEN
          RAISE EXCEPTION 'injected overlap transition failure';
        END IF;
        RETURN NEW;
      END;
      $$
    `;
    await sql`
      CREATE TRIGGER fail_atomic_signing_overlap_transition
      BEFORE UPDATE OF status
      ON mercury_management.endpoint_signing_credentials
      FOR EACH ROW EXECUTE FUNCTION mercury_management.fail_atomic_signing_overlap_transition()
    `;
    try {
      await expect(
        service.registerEndpointSigningCredential(principal, tenant.id, {
          endpointId,
          secretPointer: '/atomic-pg-signing-failed-overlap',
        }),
      ).rejects.toThrow('injected overlap transition failure');
    } finally {
      await sql`
        DROP TRIGGER fail_atomic_signing_overlap_transition
        ON mercury_management.endpoint_signing_credentials
      `;
      await sql`DROP FUNCTION mercury_management.fail_atomic_signing_overlap_transition()`;
    }
    const failedOverlapId = generatedIds.at(-1);
    expect(failedOverlapId).toBeDefined();
    expect(await repository.getEndpointSigningCredential(failedOverlapId as string)).toBeUndefined();
    expect(await repository.getEndpoint(endpointId)).toMatchObject({ signingCredentialId: first.id });
    expect(await repository.getEndpointSigningCredential(first.id)).toMatchObject({ status: 'live' });
    published = await compiler.compileAndPublish(topology);
    expect(published.generation.previousGeneration).toBe(previousGeneration);
    previousGeneration = published.generation.generation;
    expect(activeSigningRef()).toBe('/atomic-pg-signing-v1');

    const second = await service.registerEndpointSigningCredential(principal, tenant.id, {
      endpointId,
      secretPointer: '/atomic-pg-signing-v2',
    });
    expect(await repository.getEndpoint(endpointId)).toMatchObject({ signingCredentialId: second.id });
    expect(await repository.getEndpointSigningCredential(first.id)).toMatchObject({
      status: 'overlap',
      overlapUntil: new Date('2026-07-31T01:00:00.000Z'),
    });
    published = await compiler.compileAndPublish(topology);
    expect(published.generation.previousGeneration).toBe(previousGeneration);
    expect(activeSigningRef()).toBe('/atomic-pg-signing-v2');

    previousGeneration = published.generation.generation;
    const contenders = await Promise.allSettled([
      repository.rotateEndpointSigningCredential({
        id: '00000000-0000-4000-9000-000000000901',
        accountId: account.id,
        tenantId: tenant.id,
        endpointId,
        expectedCurrentCredentialId: second.id,
        secretPointer: '/atomic-pg-signing-v3-a',
        rotatedAt: new Date('2026-07-29T01:02:00.000Z'),
        overlapUntil: new Date('2026-07-31T01:02:00.000Z'),
      }),
      repository.rotateEndpointSigningCredential({
        id: '00000000-0000-4000-9000-000000000902',
        accountId: account.id,
        tenantId: tenant.id,
        endpointId,
        expectedCurrentCredentialId: second.id,
        secretPointer: '/atomic-pg-signing-v3-b',
        rotatedAt: new Date('2026-07-29T01:02:00.000Z'),
        overlapUntil: new Date('2026-07-31T01:02:00.000Z'),
      }),
    ]);
    const winners = contenders.filter(result => result.status === 'fulfilled');
    const losers = contenders.filter(result => result.status === 'rejected');
    expect(winners).toHaveLength(1);
    expect(losers).toHaveLength(1);
    expect(losers[0]).toMatchObject({ status: 'rejected', reason: { code: 'conflict' } });
    const winner = winners[0]?.status === 'fulfilled' ? winners[0].value : undefined;
    expect(winner).toBeDefined();
    expect(await repository.getEndpoint(endpointId)).toMatchObject({ signingCredentialId: winner?.id });
    expect(await repository.getEndpointSigningCredential(second.id)).toMatchObject({ status: 'overlap' });
    published = await compiler.compileAndPublish(topology);
    expect(published.generation.previousGeneration).toBe(previousGeneration);
    expect(activeSigningRef()).toBe(winner?.secretPointer);
  }, 120_000);
});
