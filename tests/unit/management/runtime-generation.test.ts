import { describe, expect, test } from 'bun:test';
import type { LandscapeRuntimeConfig } from '../../../src/domain/index.ts';
import { MercuryConfigurationCompiler } from '../../../src/management/compiler.ts';
import { InMemoryManagementRepository } from '../../../src/management/memory-repository.ts';
import {
  LocalLandscapeConfigWriter,
  MercuryManagementEndpointRefresher,
  type RuntimeGenerationTarget,
  toLandscapeRuntimeConfig,
} from '../../../src/management/runtime-generation.ts';
import { ManagementService } from '../../../src/management/service.ts';
import type {
  LandscapeAcknowledgement,
  LandscapeConfigDocument,
  LandscapeTopology,
} from '../../../src/management/types.ts';

const document: LandscapeConfigDocument = {
  generation: 7,
  landscape: 'raichu',
  contentHash: 'revision-7',
  createdAt: '2026-07-29T00:00:00.000Z',
  tenants: [
    {
      tenantId: 'tenant-1',
      name: 'internal/nitroso',
      intakeSlug: 'nitroso',
      homeVlandscape: 'mew',
      quota: {
        intakeRps: 50,
        burst: 200,
        managementRps: 20,
        retryWindowSeconds: 259_200,
        dedupWindowSeconds: 259_200,
        retentionMonths: 2,
      },
      metering: {
        enabled: true,
        exportIntervalSeconds: 60,
        dimensions: ['intake', 'delivery'],
      },
      domains: [
        {
          hostname: 'hooks.acme.example',
          registeredUrl: 'https://hooks.acme.example',
        },
      ],
      providerCredentials: [
        {
          provider: 'stripe',
          generation: 2,
          secretPointer: '/nitroso-stripe-current',
          status: 'live',
        },
      ],
      routes: [
        {
          routeId: 'route-1',
          path: '/webhook/stripe',
          registeredUrl: 'https://hooks.acme.example/webhook/stripe',
          provider: 'stripe',
          providerCredentialPointers: ['/nitroso-stripe-current'],
          endpoints: [
            {
              endpointId: 'local',
              address: 'http://checkout.zinc.svc.cluster.local/internal/webhooks/stripe',
              addressKind: 'local',
              canonicalUrl: 'https://checkout.zinc.p.mew.cluster.atomi.cloud/internal/webhooks/stripe',
              signingSecretPointer: '/nitroso-signing-local',
            },
            {
              endpointId: 'canonical',
              address: 'https://checkout.zinc.p.mew.cluster.atomi.cloud/internal/webhooks/stripe',
              addressKind: 'canonical',
              canonicalUrl: 'https://checkout.zinc.p.mew.cluster.atomi.cloud/internal/webhooks/stripe',
              signingSecretPointer: '/nitroso-signing-canonical',
            },
            {
              endpointId: 'external',
              address: 'https://receiver.example/hooks',
              addressKind: 'external',
              canonicalUrl: 'https://receiver.example/hooks',
              signingSecretPointer: '/nitroso-signing-external',
            },
          ],
        },
      ],
    },
  ],
};

class MemoryRuntimeTarget implements RuntimeGenerationTarget {
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

class FailOnceAcknowledgementRepository extends InMemoryManagementRepository {
  public failNextAcknowledgement = true;

  public override async saveLandscapeAcknowledgement(
    acknowledgement: LandscapeAcknowledgement,
  ): Promise<LandscapeAcknowledgement> {
    if (this.failNextAcknowledgement) {
      this.failNextAcknowledgement = false;
      throw new Error('Neon acknowledgement unavailable');
    }
    return super.saveLandscapeAcknowledgement(acknowledgement);
  }
}

describe('management to local runtime generation seam', () => {
  test('converts the complete document losslessly into runtime cardinality and verifier identity', () => {
    const runtime = toLandscapeRuntimeConfig(document);
    expect(runtime).toMatchObject({
      generation: 7,
      landscape: 'raichu',
      compiledAtMs: Date.parse(document.createdAt),
      sourceRevision: 'revision-7',
      tenants: [
        {
          id: 'tenant-1',
          slug: 'nitroso',
          registeredDomains: ['hooks.acme.example'],
          intakeRps: 50,
          intakeBurst: 200,
          retryWindowMs: 259_200_000,
          routes: [
            {
              id: 'route-1',
              path: '/webhook/stripe',
              canonicalPath: '/t/nitroso/webhook/stripe',
              registeredUrl: 'https://hooks.acme.example/webhook/stripe',
              verificationSecretRef: '/nitroso-stripe-current',
            },
          ],
        },
      ],
    });
    const endpoints = runtime.tenants[0]?.routes[0]?.endpoints;
    expect(endpoints?.map(endpoint => endpoint.addressKind)).toEqual(['local', 'canonical', 'external']);
    expect(endpoints).toHaveLength(3);
  });

  test('stages locally, CAS-flips, reads back before ack, and retains the previous generation', async () => {
    const target = new MemoryRuntimeTarget('raichu');
    const writer = new LocalLandscapeConfigWriter(target);
    await writer.writeCompleteGeneration(document);
    expect(await writer.flipGeneration('raichu', 7, 'revision-7')).toEqual({
      activated: true,
      acknowledged: true,
    });
    expect(target.active?.generation).toBe(7);
    const until = new Date('2026-07-31T00:00:00.000Z');
    await writer.retainPreviousGeneration('raichu', 6, until);
    expect(target.retention.get(6)).toEqual(until);
    await expect(
      writer.writeCompleteGeneration({
        ...document,
        landscape: 'ampharos',
      }),
    ).rejects.toMatchObject({ code: 'invalid' });
  });

  test('421 refresher recompiles only local topology and returns the requested registration', async () => {
    let id = 0;
    const repository = new InMemoryManagementRepository();
    const service = new ManagementService(repository, {
      clock: () => new Date('2026-07-29T00:00:00.000Z'),
      idFactory: () => `00000000-0000-4000-8000-${(++id).toString().padStart(12, '0')}`,
    });
    const provisioned = await service.provisionDefaultInternalAccount('bootstrap');
    const principal = await service.authenticateBearer('Bearer bootstrap');
    const tenant = await service.createOrAdoptTenant({
      accountId: provisioned.account.id,
      name: 'internal/nitroso',
      intakeSlug: 'nitroso',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    const providerCredential = await service.registerProviderCredential(principal, tenant.id, {
      provider: 'stripe',
      secretPointer: '/mew-stripe',
    });
    const route = await service.upsertRoute(principal, tenant.id, {
      path: '/webhook/stripe',
      registeredUrl: 'https://hooks.mercury.p.mew.cluster.atomi.cloud/t/nitroso/webhook/stripe',
      provider: 'stripe',
      providerCredentialId: providerCredential.id,
    });
    await repository.saveEndpointSigningCredential({
      id: '00000000-0000-4000-8000-000000000099',
      accountId: provisioned.account.id,
      tenantId: tenant.id,
      endpointId: '00000000-0000-4000-8000-000000000098',
      generation: 1,
      secretPointer: '/mew-signing',
      status: 'live',
      createdAt: new Date('2026-07-29T00:00:00.000Z'),
    });
    const endpoint = await service.upsertEndpoint(principal, tenant.id, route.id, {
      id: '00000000-0000-4000-8000-000000000098',
      target: {
        kind: 'coordinate',
        service: 'zinc',
        module: 'checkout',
        canonicalVlandscape: 'mew',
      },
      signingCredentialId: '00000000-0000-4000-8000-000000000099',
    });
    const topology: LandscapeTopology = {
      landscapes: ['raichu'],
      services: {
        'zinc/checkout': {
          module: 'checkout',
          localLandscapes: ['raichu'],
          localAddressByLandscape: {
            raichu: 'http://checkout.zinc.svc.cluster.local',
          },
          canonicalVlandscape: 'mew',
          canonicalAddress: 'https://checkout.zinc.p.mew.cluster.atomi.cloud',
        },
      },
    };
    const target = new MemoryRuntimeTarget('raichu');
    const compiler = new MercuryConfigurationCompiler(repository, new LocalLandscapeConfigWriter(target), {
      clock: () => new Date('2026-07-29T00:00:01.000Z'),
    });
    const refresher = new MercuryManagementEndpointRefresher('raichu', topology, compiler);
    const refreshed = await refresher.refreshEndpoint({
      tenantId: tenant.id,
      routeId: route.id,
      endpointId: endpoint.id,
    });
    expect(await refreshed.isOk()).toBe(true);
    expect(await refreshed.unwrap()).toMatchObject({
      id: endpoint.id,
      addressKind: 'local',
      canonicalUrl: 'https://checkout.zinc.p.mew.cluster.atomi.cloud/internal/webhooks/stripe',
    });

    const absent = await refresher.refreshEndpoint({
      tenantId: tenant.id,
      routeId: route.id,
      endpointId: 'sibling-endpoint',
    });
    expect(await absent.isErr()).toBe(true);
    expect((await absent.unwrapErr()).message).toContain('registration is absent');
  });

  test('retains a deleted last-provider route with zero endpoints for 72 hours through the production writer seam', async () => {
    let now = new Date('2026-07-29T00:00:00.000Z');
    let id = 0;
    const repository = new InMemoryManagementRepository();
    const service = new ManagementService(repository, {
      clock: () => new Date(now),
      idFactory: () => `00000000-0000-4000-8000-${(++id).toString().padStart(12, '0')}`,
    });
    const provisioned = await service.provisionDefaultInternalAccount('bootstrap');
    const principal = await service.authenticateBearer('Bearer bootstrap');
    const tenant = await service.createOrAdoptTenant({
      accountId: provisioned.account.id,
      name: 'internal/orphan',
      intakeSlug: 'orphan',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    const providerCredential = await service.registerProviderCredential(principal, tenant.id, {
      provider: 'stripe',
      secretPointer: '/orphan-stripe',
    });
    const route = await service.upsertRoute(principal, tenant.id, {
      path: '/webhook/stripe',
      registeredUrl: 'https://hooks.mercury.p.mew.cluster.atomi.cloud/t/orphan/webhook/stripe',
      provider: 'stripe',
      providerCredentialId: providerCredential.id,
    });
    await repository.saveEndpointSigningCredential({
      id: 'orphan-signing',
      accountId: provisioned.account.id,
      tenantId: tenant.id,
      endpointId: 'orphan-endpoint',
      generation: 1,
      secretPointer: '/orphan-signing',
      status: 'live',
      createdAt: now,
    });
    await service.upsertEndpoint(principal, tenant.id, route.id, {
      id: 'orphan-endpoint',
      target: {
        kind: 'coordinate',
        service: 'zinc',
        module: 'checkout',
        canonicalVlandscape: 'mew',
      },
      signingCredentialId: 'orphan-signing',
    });
    const target = new MemoryRuntimeTarget('raichu');
    const compiler = new MercuryConfigurationCompiler(repository, new LocalLandscapeConfigWriter(target), {
      clock: () => new Date(now),
    });
    const topology: LandscapeTopology = {
      landscapes: ['raichu'],
      services: {
        'zinc/checkout': {
          module: 'checkout',
          localLandscapes: ['raichu'],
          canonicalVlandscape: 'mew',
        },
      },
    };
    await compiler.compileAndPublish(topology);
    await service.deleteRoute(principal, tenant.id, route.id);
    now = new Date(now.getTime() + 1_000);
    await compiler.compileAndPublish(topology);
    const orphaned = target.active?.tenants[0]?.routes[0];
    expect(orphaned).toMatchObject({ id: route.id, provider: 'stripe', endpoints: [] });
    expect(orphaned?.orphanedUntilMs).toBe(now.getTime() + 72 * 60 * 60 * 1000);
    expect(
      (orphaned as typeof orphaned & { verificationSecretRefs?: readonly string[] })?.verificationSecretRefs,
    ).toEqual(['/orphan-stripe']);

    now = new Date(now.getTime() + 72 * 60 * 60 * 1000 + 1);
    await compiler.compileAndPublish(topology);
    expect(target.active?.tenants[0]?.routes).toEqual([]);
  });

  test('journals activated-but-unacknowledged Redis state and reconciles it without marking failed', async () => {
    const repository = new FailOnceAcknowledgementRepository();
    const target = new MemoryRuntimeTarget('raichu');
    const compiler = new MercuryConfigurationCompiler(repository, new LocalLandscapeConfigWriter(target), {
      clock: () => new Date('2026-07-29T00:00:00.000Z'),
    });
    const topology: LandscapeTopology = { landscapes: ['raichu'], services: {} };

    await expect(compiler.compileAndPublish(topology)).rejects.toMatchObject({ code: 'compiler_failed' });
    expect(target.active?.generation).toBe(1);
    expect((await repository.getConfigGeneration(1))?.status).toBe('activated');

    const recovered = await compiler.compileAndPublish(topology);
    expect(recovered.generation.generation).toBe(2);
    expect((await repository.getConfigGeneration(1))?.status).toBe('superseded');
    expect((await repository.getConfigGeneration(1))?.status).not.toBe('failed');
  });

  test('runs provider readiness preflight after staging and before CAS activation', async () => {
    const repository = new InMemoryManagementRepository();
    const target = new MemoryRuntimeTarget('raichu');
    const compiler = new MercuryConfigurationCompiler(repository, new LocalLandscapeConfigWriter(target), {
      preActivate: async () => {
        throw new Error('provider secret malformed');
      },
    });
    await expect(compiler.compileAndPublish({ landscapes: ['raichu'], services: {} })).rejects.toMatchObject({
      code: 'compiler_failed',
    });
    expect(target.active).toBeNull();
    expect((await repository.getConfigGeneration(1))?.status).toBe('failed');
  });
});
