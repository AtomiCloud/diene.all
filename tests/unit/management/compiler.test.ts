import { describe, expect, test } from 'bun:test';
import { InMemoryLandscapeConfigWriter, MercuryConfigurationCompiler } from '../../../src/management/compiler.ts';
import {
  type EndpointSigningCredentialRotationCheckpoint,
  InMemoryManagementRepository,
} from '../../../src/management/memory-repository.ts';
import type { EndpointSigningCredentialRotation } from '../../../src/management/repository.ts';
import { ManagementService } from '../../../src/management/service.ts';
import {
  type AuthenticatedPrincipal,
  type LandscapeTopology,
  MAX_CONFIG_DOCUMENT_BYTES,
} from '../../../src/management/types.ts';

function ids(): () => string {
  let value = 0;
  return () => `00000000-0000-4000-8000-${(++value).toString().padStart(12, '0')}`;
}

function topologyFor(landscape: 'raichu' | 'ampharos'): LandscapeTopology {
  return {
    landscapes: [landscape],
    services: {
      'zinc/checkout': {
        module: 'checkout',
        localLandscapes: landscape === 'raichu' ? ['raichu'] : [],
        localAddressByLandscape:
          landscape === 'raichu'
            ? {
                raichu: 'http://checkout.zinc.svc.cluster.local',
              }
            : {},
        canonicalVlandscape: 'mew',
        canonicalAddress: 'https://checkout.zinc.p.mew.cluster.atomi.cloud',
      },
    },
  };
}

class FaultInjectingEndpointSigningRepository extends InMemoryManagementRepository {
  public failAt?: EndpointSigningCredentialRotationCheckpoint;
  public failAfterCommit = false;

  protected override endpointSigningCredentialRotationCheckpoint(
    checkpoint: EndpointSigningCredentialRotationCheckpoint,
  ): void {
    if (this.failAt === checkpoint) {
      this.failAt = undefined;
      throw new Error(`injected endpoint signing rotation failure at ${checkpoint}`);
    }
  }

  public override async rotateEndpointSigningCredential(rotation: EndpointSigningCredentialRotation) {
    const credential = await super.rotateEndpointSigningCredential(rotation);
    if (this.failAfterCommit) {
      this.failAfterCommit = false;
      throw new Error('injected lost endpoint signing rotation response');
    }
    return credential;
  }
}

describe('Mercury configuration compiler', () => {
  test('preserves all endpoint registrations while changing only address resolution', async () => {
    const repository = new InMemoryManagementRepository();
    const service = new ManagementService(repository, {
      clock: () => new Date('2026-07-29T00:00:00.000Z'),
      idFactory: ids(),
    });
    const { account } = await service.provisionDefaultInternalAccount('boot');
    const principal = (await service.authenticateBearer('Bearer boot')) as AuthenticatedPrincipal;
    const tenant = await service.createOrAdoptTenant({
      accountId: account.id,
      name: 'internal/nitroso',
      intakeSlug: 'nitroso',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    const providerCredential = await service.registerProviderCredential(principal, tenant.id, {
      provider: 'stripe',
      secretPointer: '/mew-stripe-gen-1',
    });
    const route = await service.upsertRoute(principal, tenant.id, {
      path: '/webhook/stripe/complete',
      registeredUrl: 'https://hooks.mercury.p.mew.cluster.atomi.cloud/t/nitroso/webhook/stripe/complete',
      provider: 'stripe',
      scheme: 'hmac-sha256',
      providerCredentialId: providerCredential.id,
    });
    await service.registerProviderCredential(principal, tenant.id, {
      provider: 'stripe',
      secretPointer: '/mew-stripe-gen-2',
    });
    for (const id of ['endpoint-a', 'endpoint-b', 'endpoint-c']) {
      const signingCredentialId = `signing-${id}`;
      await repository.saveEndpointSigningCredential({
        id: signingCredentialId,
        accountId: account.id,
        tenantId: tenant.id,
        endpointId: id,
        generation: 1,
        secretPointer: `/mew-signing-${id}`,
        status: 'live',
        createdAt: new Date('2026-07-29T00:00:00.000Z'),
      });
      await service.upsertEndpoint(principal, tenant.id, route.id, {
        id,
        target: {
          kind: 'coordinate',
          service: 'zinc',
          module: 'checkout',
          canonicalVlandscape: 'mew',
        },
        signingCredentialId,
      });
    }

    const localWriter = new InMemoryLandscapeConfigWriter();
    const localCompiler = new MercuryConfigurationCompiler(repository, localWriter, {
      clock: () => new Date('2026-07-29T00:00:01.000Z'),
    });
    const remoteWriter = new InMemoryLandscapeConfigWriter();
    const remoteCompiler = new MercuryConfigurationCompiler(repository, remoteWriter, {
      clock: () => new Date('2026-07-29T00:00:01.000Z'),
    });
    const localResult = await localCompiler.compileAndPublish(topologyFor('raichu'));
    const remoteResult = await remoteCompiler.compileAndPublish(topologyFor('ampharos'));
    expect(localResult.acknowledgedLandscapes).toEqual(['raichu']);
    expect(remoteResult.acknowledgedLandscapes).toEqual(['ampharos']);

    const local = localWriter.document('raichu', localResult.generation.generation)?.tenants[0]?.routes[0]?.endpoints;
    const remote = remoteWriter.document('ampharos', remoteResult.generation.generation)?.tenants[0]?.routes[0]
      ?.endpoints;
    expect(local?.length).toBe(3);
    expect(remote?.length).toBe(3);
    expect(local?.map(item => item.endpointId)).toEqual(['endpoint-a', 'endpoint-b', 'endpoint-c']);
    expect(local?.every(item => item.addressKind === 'local')).toBe(true);
    expect(remote?.every(item => item.addressKind === 'canonical')).toBe(true);
    expect(local?.[0]?.address).toBe('http://checkout.zinc.svc.cluster.local/internal/webhooks/stripe');
    expect(remote?.[0]?.address).toBe('https://checkout.zinc.p.mew.cluster.atomi.cloud/internal/webhooks/stripe');
    expect(localWriter.document('raichu', localResult.generation.generation)?.tenants[0]?.providerCredentials).toEqual([
      {
        provider: 'stripe',
        generation: 2,
        secretPointer: '/mew-stripe-gen-2',
        status: 'live',
      },
      {
        provider: 'stripe',
        generation: 1,
        secretPointer: '/mew-stripe-gen-1',
        status: 'overlap',
      },
    ]);

    const serialized = JSON.stringify([...localResult.documents, ...remoteResult.documents]);
    expect(serialized).toContain('/mew-stripe');
    expect(serialized).not.toContain('boot');

    const afterOverlap = await new MercuryConfigurationCompiler(repository, localWriter, {
      clock: () => new Date('2026-08-01T00:00:00.000Z'),
    }).compileAndPublish(topologyFor('raichu'));
    expect(afterOverlap.documents[0]?.tenants[0]?.routes[0]?.providerCredentialPointers).toEqual(['/mew-stripe-gen-2']);
    expect(afterOverlap.documents[0]?.tenants[0]?.providerCredentials.map(item => item.generation)).toEqual([2]);
  });

  test('keeps a bound endpoint compilable across every atomic signing-rotation failure boundary', async () => {
    const repository = new FaultInjectingEndpointSigningRepository();
    const service = new ManagementService(repository, {
      clock: () => new Date('2026-07-29T00:00:00.000Z'),
      idFactory: ids(),
    });
    const { account } = await service.provisionDefaultInternalAccount('boot');
    const principal = await service.authenticateBearer('Bearer boot');
    const tenant = await service.createOrAdoptTenant({
      accountId: account.id,
      name: 'internal/atomic-signing',
      intakeSlug: 'atomic-signing',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    const route = await service.upsertRoute(principal, tenant.id, {
      path: '/webhook/stripe',
      registeredUrl: 'https://hooks.mercury.p.mew.cluster.atomi.cloud/t/atomic-signing/webhook/stripe',
      provider: 'stripe',
    });
    const endpointId = 'atomic-signing-endpoint';
    const first = await service.registerEndpointSigningCredential(principal, tenant.id, {
      endpointId,
      secretPointer: '/atomic-signing-v1',
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
    const writer = new InMemoryLandscapeConfigWriter();
    const compiler = new MercuryConfigurationCompiler(repository, writer, {
      clock: () => new Date('2026-07-29T00:01:00.000Z'),
    });
    let published = await compiler.compileAndPublish(topologyFor('raichu'));
    let previousGeneration = published.generation.generation;
    expect(published.documents[0]?.tenants[0]?.routes[0]?.endpoints[0]?.signingSecretPointer).toBe(
      '/atomic-signing-v1',
    );

    for (const checkpoint of ['after-new-credential', 'after-endpoint-rebind', 'after-previous-overlap'] as const) {
      repository.failAt = checkpoint;
      await expect(
        service.registerEndpointSigningCredential(principal, tenant.id, {
          endpointId,
          secretPointer: `/atomic-signing-failed-${checkpoint}`,
        }),
      ).rejects.toThrow(`injected endpoint signing rotation failure at ${checkpoint}`);
      expect(await repository.getEndpoint(endpointId)).toMatchObject({ signingCredentialId: first.id });
      expect(await repository.getEndpointSigningCredential(first.id)).toMatchObject({ status: 'live' });
      expect(await repository.listEndpointSigningCredentials(tenant.id)).toHaveLength(1);

      published = await compiler.compileAndPublish(topologyFor('raichu'));
      expect(published.generation.previousGeneration).toBe(previousGeneration);
      expect(published.documents[0]?.tenants[0]?.routes[0]?.endpoints[0]?.signingSecretPointer).toBe(
        '/atomic-signing-v1',
      );
      previousGeneration = published.generation.generation;
    }

    repository.failAfterCommit = true;
    await expect(
      service.registerEndpointSigningCredential(principal, tenant.id, {
        endpointId,
        secretPointer: '/atomic-signing-v2',
      }),
    ).rejects.toThrow('injected lost endpoint signing rotation response');
    const live = (await repository.listEndpointSigningCredentials(tenant.id)).find(
      credential => credential.status === 'live',
    );
    expect(live).toBeDefined();
    expect(live?.id).not.toBe(first.id);
    expect(await repository.getEndpoint(endpointId)).toMatchObject({ signingCredentialId: live?.id });
    expect(await repository.getEndpointSigningCredential(first.id)).toMatchObject({
      status: 'overlap',
      overlapUntil: new Date('2026-07-31T00:00:00.000Z'),
    });

    published = await compiler.compileAndPublish(topologyFor('raichu'));
    expect(published.generation.previousGeneration).toBe(previousGeneration);
    expect(published.documents[0]?.tenants[0]?.routes[0]?.endpoints[0]?.signingSecretPointer).toBe(
      '/atomic-signing-v2',
    );
  });

  test('rejects a coordinate absent from supplied topology', async () => {
    const repository = new InMemoryManagementRepository();
    const service = new ManagementService(repository, {
      idFactory: ids(),
    });
    const { account } = await service.provisionDefaultInternalAccount('boot');
    const principal = await service.authenticateBearer('Bearer boot');
    const tenant = await service.createOrAdoptTenant({
      accountId: account.id,
      name: 'internal/nitroso',
      intakeSlug: 'nitroso',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    const route = await service.upsertRoute(principal, tenant.id, {
      path: '/webhook/stripe',
      registeredUrl: 'https://hooks.mercury.p.mew.cluster.atomi.cloud/t/nitroso/webhook/stripe',
      provider: 'stripe',
    });
    await repository.saveEndpointSigningCredential({
      id: 'signing-unknown',
      accountId: account.id,
      tenantId: tenant.id,
      endpointId: 'endpoint-unknown',
      generation: 1,
      secretPointer: '/mew-signing',
      status: 'live',
      createdAt: new Date(),
    });
    await service.upsertEndpoint(principal, tenant.id, route.id, {
      id: 'endpoint-unknown',
      target: {
        kind: 'coordinate',
        service: 'unknown',
        module: 'checkout',
        canonicalVlandscape: 'mew',
      },
      signingCredentialId: 'signing-unknown',
    });
    const compiler = new MercuryConfigurationCompiler(repository, new InMemoryLandscapeConfigWriter());
    await expect(compiler.compileAndPublish(topologyFor('raichu'))).rejects.toMatchObject({
      code: 'invalid',
    });
  });

  test('rejects a topology containing more than its one trusted local landscape', async () => {
    const compiler = new MercuryConfigurationCompiler(
      new InMemoryManagementRepository(),
      new InMemoryLandscapeConfigWriter(),
    );
    await expect(
      compiler.compileAndPublish({
        landscapes: ['raichu', 'ampharos'],
        services: {},
      }),
    ).rejects.toMatchObject({
      code: 'invalid',
      message: 'compiler topology must contain exactly one local landscape',
    });
  });

  test('rejects an oversized compiled document before staging or ledger publication', async () => {
    const repository = new InMemoryManagementRepository();
    const service = new ManagementService(repository, { idFactory: ids() });
    const { account } = await service.provisionDefaultInternalAccount('boot');
    const tenant = await service.createOrAdoptTenant({
      accountId: account.id,
      name: 'internal/oversized',
      intakeSlug: 'oversized',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    const now = new Date('2026-07-29T00:00:00.000Z');
    await repository.saveCustomDomain({
      id: 'oversized-domain',
      tenantId: tenant.id,
      hostname: 'oversized.example',
      registeredUrl: `https://oversized.example/${'x'.repeat(MAX_CONFIG_DOCUMENT_BYTES)}`,
      intakeTarget: 'hooks.mercury.p.mew.cluster.atomi.cloud',
      challengeTarget: 'mercury-domain-oversized.domain-validation.hooks.mercury.p.mew.cluster.atomi.cloud',
      certificateSecretPointer: '/oversized-tls',
      status: 'active',
      verificationTokenHash: 'hash',
      pendingUntil: new Date(now.getTime() + 60_000),
      verifiedAt: now,
      activatedAt: now,
      createdAt: now,
      updatedAt: now,
    });
    const writer = new InMemoryLandscapeConfigWriter();
    const compiler = new MercuryConfigurationCompiler(repository, writer);
    await expect(compiler.compileAndPublish(topologyFor('raichu'))).rejects.toMatchObject({ code: 'invalid' });
    expect(await repository.listConfigGenerations()).toEqual([]);
    expect(writer.currentGeneration('raichu')).toBeUndefined();
  });

  test('rechecks opaque provider ownership during compilation after repository tampering', async () => {
    const repository = new InMemoryManagementRepository();
    const service = new ManagementService(repository, { idFactory: ids() });
    await service.provisionDefaultInternalAccount('boot');
    const accountA = await service.createAccount({ name: 'external/compiler-a', kind: 'external' });
    const accountB = await service.createAccount({ name: 'external/compiler-b', kind: 'external' });
    const tenantA = await service.createOrAdoptTenant({
      accountId: accountA.id,
      name: 'external/compiler-a',
      intakeSlug: 'compiler-a',
      source: 'api',
      homeVlandscape: 'mew',
    });
    const tenantB = await service.createOrAdoptTenant({
      accountId: accountB.id,
      name: 'external/compiler-b',
      intakeSlug: 'compiler-b',
      source: 'api',
      homeVlandscape: 'mew',
    });
    const now = new Date('2026-07-29T00:00:00.000Z');
    await repository.saveProviderCredential({
      id: 'compiler-b-provider',
      accountId: accountB.id,
      tenantId: tenantB.id,
      provider: 'stripe',
      generation: 1,
      secretPointer: '/compiler-b-stripe',
      status: 'live',
      createdAt: now,
    });
    await repository.saveRoute({
      id: 'tampered-route',
      tenantId: tenantA.id,
      path: '/webhook/stripe',
      registeredUrl: 'https://hooks.mercury.p.mew.cluster.atomi.cloud/t/compiler-a/webhook/stripe',
      provider: 'stripe',
      providerCredentialId: 'compiler-b-provider',
      createdAt: now,
      updatedAt: now,
    });
    await expect(
      new MercuryConfigurationCompiler(repository, new InMemoryLandscapeConfigWriter()).compileAndPublish(
        topologyFor('raichu'),
      ),
    ).rejects.toMatchObject({ code: 'forbidden' });
  });

  test('publishes only an active custom-domain claim as an authoritative host hint', async () => {
    const repository = new InMemoryManagementRepository();
    const service = new ManagementService(repository, { idFactory: ids() });
    const { account } = await service.provisionDefaultInternalAccount('boot');
    const principal = await service.authenticateBearer('Bearer boot');
    const tenant = await service.createOrAdoptTenant({
      accountId: account.id,
      name: 'internal/pending-domain',
      intakeSlug: 'pending-domain',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    const claim = await service.registerCustomDomain(principal, tenant.id, { hostname: 'unproved.example' });
    const compiler = new MercuryConfigurationCompiler(repository, new InMemoryLandscapeConfigWriter());
    const pending = await compiler.compileAndPublish(topologyFor('raichu'));
    expect(pending.documents[0]?.tenants[0]?.domains).toEqual([]);
    const now = new Date('2026-07-29T00:00:00.000Z');
    await repository.saveCustomDomain({
      ...claim.domain,
      status: 'verified',
      verifiedAt: now,
      updatedAt: now,
    });
    const verified = await compiler.compileAndPublish(topologyFor('raichu'));
    expect(verified.documents[0]?.tenants[0]?.domains).toEqual([]);
    await repository.saveCustomDomain({
      ...claim.domain,
      status: 'active',
      verifiedAt: now,
      activatedAt: now,
      updatedAt: now,
    });
    const active = await compiler.compileAndPublish(topologyFor('raichu'));
    expect(active.documents[0]?.tenants[0]?.domains).toEqual([
      { hostname: 'unproved.example', registeredUrl: 'https://unproved.example' },
    ]);
  });
});
