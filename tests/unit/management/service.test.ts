import { describe, expect, test } from 'bun:test';
import { InMemoryManagementRepository } from '../../../src/management/memory-repository.ts';
import { ManagementService, type ManagementServiceOptions } from '../../../src/management/service.ts';
import {
  DOMAIN_CLAIM_TTL_SECONDS,
  MAX_RETRY_WINDOW_SECONDS,
  MAX_ROUTES_PER_TENANT,
} from '../../../src/management/types.ts';

function harness(options: ManagementServiceOptions = {}) {
  let now = new Date('2026-07-29T00:00:00.000Z');
  let nextId = 0;
  const repository = new InMemoryManagementRepository();
  const service = new ManagementService(repository, {
    ...options,
    clock: () => new Date(now),
    idFactory: () => `00000000-0000-4000-8000-${(++nextId).toString().padStart(12, '0')}`,
    tokenFactory: () => `token-${nextId}`,
  });
  return {
    repository,
    service,
    advance(seconds: number) {
      now = new Date(now.getTime() + seconds * 1000);
    },
  };
}

describe('Mercury management service', () => {
  test('provisions one default internal account and adopts its tenant idempotently', async () => {
    const { repository, service } = harness();
    const provisioned = await service.provisionDefaultInternalAccount('boot');
    const repeated = await service.provisionDefaultInternalAccount('ignored');
    expect(repeated.account.id).toBe(provisioned.account.id);
    expect(repeated.issued).toBeUndefined();
    expect((await repository.listAccounts()).map(item => item.name)).toEqual(['internal/default']);

    const first = await service.createOrAdoptTenant({
      accountId: provisioned.account.id,
      name: 'internal/nitroso',
      intakeSlug: 'nitroso',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    const adopted = await service.createOrAdoptTenant({
      accountId: provisioned.account.id,
      name: 'internal/nitroso',
      intakeSlug: 'nitroso',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    expect(adopted.id).toBe(first.id);
    expect((await repository.listTenants()).length).toBe(1);
  });

  test('rejects a home move and requires new tenant plus cutover', async () => {
    const { service } = harness();
    const { account } = await service.provisionDefaultInternalAccount('boot');
    await service.createOrAdoptTenant({
      accountId: account.id,
      name: 'internal/nitroso',
      intakeSlug: 'nitroso',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    await expect(
      service.createOrAdoptTenant({
        accountId: account.id,
        name: 'internal/nitroso',
        intakeSlug: 'nitroso',
        source: 'cr',
        homeVlandscape: 'ditto',
      }),
    ).rejects.toMatchObject({
      code: 'immutable_home',
    });
    await expect(
      service.createOrAdoptTenant({
        accountId: account.id,
        name: 'internal/nitroso',
        intakeSlug: 'renamed',
        source: 'cr',
        homeVlandscape: 'mew',
      }),
    ).rejects.toMatchObject({ code: 'immutable_home' });
  });

  test('authenticates only native management bearer credentials during overlap', async () => {
    const { service, advance } = harness();
    const { account } = await service.provisionDefaultInternalAccount('old-token');
    const principal = await service.authenticateBearer('Bearer old-token');
    const rotated = await service.rotateManagementCredential(principal, account.id, { overlapSeconds: 10 });

    expect((await service.authenticateBearer('Bearer old-token')).accountId).toBe(account.id);
    expect((await service.authenticateBearer(`Bearer ${rotated.token}`)).accountId).toBe(account.id);
    await expect(service.authenticateBearer('Basic b2xkLXRva2Vu')).rejects.toMatchObject({ code: 'unauthorized' });

    advance(11);
    await expect(service.authenticateBearer('Bearer old-token')).rejects.toMatchObject({ code: 'unauthorized' });
    expect((await service.authenticateBearer(`Bearer ${rotated.token}`)).accountId).toBe(account.id);
  });

  test('validates v1 quota scalars', async () => {
    const { service } = harness();
    const { account } = await service.provisionDefaultInternalAccount('boot');
    const principal = await service.authenticateBearer('Bearer boot');
    const tenant = await service.createOrAdoptTenant({
      accountId: account.id,
      name: 'internal/nitroso',
      intakeSlug: 'nitroso',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    await expect(
      service.setQuota(principal, tenant.id, {
        intakeRps: 10,
        burst: 20,
        managementRps: 10,
        retryWindowSeconds: MAX_RETRY_WINDOW_SECONDS + 1,
        dedupWindowSeconds: MAX_RETRY_WINDOW_SECONDS,
        retentionMonths: 2,
      }),
    ).rejects.toMatchObject({ code: 'invalid' });
  });

  test('publishes only an exact canonical or ownership-verified custom URL', async () => {
    let certificateReady = false;
    const { repository, service } = harness({
      domainOwnershipVerifier: {
        async verify() {
          return { owned: true, certificateReady };
        },
      },
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
    await expect(
      service.upsertRoute(principal, tenant.id, {
        path: '/webhook/stripe',
        registeredUrl: 'https://attacker.example/t/nitroso/webhook/stripe',
        provider: 'stripe',
      }),
    ).rejects.toMatchObject({ code: 'invalid' });

    const claim = await service.registerCustomDomain(principal, tenant.id, {
      hostname: 'hooks.acme.example',
    });
    expect(claim.domain.intakeTarget).toBe('hooks.mercury.p.mew.cluster.atomi.cloud');
    expect(claim.records).toEqual([
      {
        type: 'CNAME',
        name: 'hooks.acme.example',
        target: claim.domain.intakeTarget,
      },
      {
        type: 'CNAME',
        name: '_acme-challenge.hooks.acme.example',
        target: claim.domain.challengeTarget,
      },
    ]);
    await expect(
      service.upsertRoute(principal, tenant.id, {
        path: '/webhook/stripe',
        registeredUrl: 'https://hooks.acme.example/webhook/stripe',
        provider: 'stripe',
      }),
    ).rejects.toMatchObject({ code: 'invalid' });
    expect((await service.verifyCustomDomain(principal, tenant.id, claim.domain.id)).status).toBe('verified');
    await expect(
      service.upsertRoute(principal, tenant.id, {
        path: '/webhook/stripe',
        registeredUrl: 'https://hooks.acme.example/webhook/stripe',
        provider: 'stripe',
      }),
    ).rejects.toMatchObject({ code: 'invalid' });
    certificateReady = true;
    expect((await service.verifyCustomDomain(principal, tenant.id, claim.domain.id)).status).toBe('active');
    const route = await service.upsertRoute(principal, tenant.id, {
      path: '/webhook/stripe',
      registeredUrl: 'https://hooks.acme.example/webhook/stripe',
      provider: 'stripe',
    });
    expect(route.registeredUrl).toBe('https://hooks.acme.example/webhook/stripe');
    await expect(service.deleteCustomDomain(principal, tenant.id, claim.domain.id)).rejects.toMatchObject({
      code: 'conflict',
    });
    await service.deleteRoute(principal, tenant.id, route.id);
    await repository.saveRoute({
      ...route,
      id: '00000000-0000-4000-8000-000000000099',
      path: '/webhook/stripe/suffix',
      registeredUrl: 'https://hooks.acme.example.attacker.test/webhook/stripe/suffix',
    });
    await service.deleteCustomDomain(principal, tenant.id, claim.domain.id);
    expect(await repository.getCustomDomain(claim.domain.id)).toBeUndefined();
  });

  test('prevents tenant credential rotation from widening tenant or scope', async () => {
    const { service } = harness();
    const { account } = await service.provisionDefaultInternalAccount('boot');
    const first = await service.createOrAdoptTenant({
      accountId: account.id,
      name: 'internal/first',
      intakeSlug: 'first',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    const second = await service.createOrAdoptTenant({
      accountId: account.id,
      name: 'internal/second',
      intakeSlug: 'second',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    await service.issueManagementCredential(
      account.id,
      first.id,
      ['credentials:rotate', 'routes:read'],
      'tenant-token',
    );
    const principal = await service.authenticateBearer('Bearer tenant-token');

    await expect(service.rotateManagementCredential(principal, account.id)).rejects.toMatchObject({
      code: 'forbidden',
    });
    await expect(
      service.rotateManagementCredential(principal, account.id, { tenantId: second.id, scopes: ['routes:read'] }),
    ).rejects.toMatchObject({ code: 'forbidden' });
    await expect(
      service.rotateManagementCredential(principal, account.id, { tenantId: first.id, scopes: ['routes:write'] }),
    ).rejects.toMatchObject({ code: 'forbidden' });
    await expect(
      service.rotateManagementCredential(principal, account.id, { tenantId: first.id, scopes: ['*'] }),
    ).rejects.toMatchObject({ code: 'forbidden' });
    const narrowed = await service.rotateManagementCredential(principal, account.id, {
      tenantId: first.id,
      scopes: ['routes:read'],
    });
    expect(narrowed.credential).toMatchObject({ tenantId: first.id, scopes: ['routes:read'] });
  });

  test('rejects cross-tenant opaque provider and endpoint signing bindings', async () => {
    const { repository, service } = harness();
    await service.provisionDefaultInternalAccount('boot');
    const principal = await service.authenticateBearer('Bearer boot');
    const accountA = await service.createAccount({ name: 'external/a', kind: 'external' });
    const accountB = await service.createAccount({ name: 'external/b', kind: 'external' });
    const tenantA = await service.createOrAdoptTenant({
      accountId: accountA.id,
      name: 'external/a',
      intakeSlug: 'a',
      source: 'api',
      homeVlandscape: 'mew',
    });
    const tenantB = await service.createOrAdoptTenant({
      accountId: accountB.id,
      name: 'external/b',
      intakeSlug: 'b',
      source: 'api',
      homeVlandscape: 'mew',
    });
    await repository.saveProviderCredential({
      id: 'provider-b',
      accountId: accountB.id,
      tenantId: tenantB.id,
      provider: 'stripe',
      generation: 1,
      secretPointer: '/tenant-b-stripe',
      status: 'live',
      createdAt: new Date('2026-07-29T00:00:00.000Z'),
    });
    await expect(
      service.upsertRoute(principal, tenantA.id, {
        path: '/webhook/stripe',
        registeredUrl: 'https://hooks.mercury.p.mew.cluster.atomi.cloud/t/a/webhook/stripe',
        provider: 'stripe',
        providerCredentialId: 'provider-b',
      }),
    ).rejects.toMatchObject({ code: 'forbidden' });
    const route = await service.upsertRoute(principal, tenantA.id, {
      path: '/webhook/stripe',
      registeredUrl: 'https://hooks.mercury.p.mew.cluster.atomi.cloud/t/a/webhook/stripe',
      provider: 'stripe',
    });
    await repository.saveEndpointSigningCredential({
      id: 'signing-b',
      accountId: accountB.id,
      tenantId: tenantB.id,
      endpointId: 'endpoint-a',
      generation: 1,
      secretPointer: '/tenant-b-signing',
      status: 'live',
      createdAt: new Date('2026-07-29T00:00:00.000Z'),
    });
    await expect(
      service.upsertEndpoint(principal, tenantA.id, route.id, {
        id: 'endpoint-a',
        target: { kind: 'url', url: 'https://receiver.example/hooks' },
        signingCredentialId: 'signing-b',
      }),
    ).rejects.toMatchObject({ code: 'forbidden' });
  });

  test('provisions endpoint signing IDs before endpoint creation and rotates them within one tenant', async () => {
    const { repository, service } = harness();
    const { account } = await service.provisionDefaultInternalAccount('boot');
    const tenant = await service.createOrAdoptTenant({
      accountId: account.id,
      name: 'internal/signing',
      intakeSlug: 'signing',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    await service.issueManagementCredential(
      account.id,
      undefined,
      ['routes:write', 'secrets:provision'],
      'account-admin',
    );
    const accountAdmin = await service.authenticateBearer('Bearer account-admin');
    const endpointId = '00000000-0000-4000-8000-000000000098';
    const first = await service.registerEndpointSigningCredential(accountAdmin, tenant.id, {
      endpointId,
      secretPointer: '/signing-v1',
    });
    const second = await service.registerEndpointSigningCredential(accountAdmin, tenant.id, {
      endpointId,
      secretPointer: '/signing-v2',
    });
    expect(first).toMatchObject({ endpointId, generation: 1, status: 'live' });
    expect(second).toMatchObject({ endpointId, generation: 2, status: 'live' });
    expect(await repository.getEndpointSigningCredential(first.id)).toMatchObject({
      status: 'overlap',
      overlapUntil: new Date('2026-07-31T00:00:00.000Z'),
    });

    await expect(
      service.registerEndpointSigningCredential(accountAdmin, tenant.id, {
        endpointId,
        secretPointer: '/hierarchical/signing',
      }),
    ).rejects.toMatchObject({ code: 'invalid' });
    await service.issueManagementCredential(account.id, tenant.id, ['secrets:provision'], 'tenant-secret-admin');
    const tenantPrincipal = await service.authenticateBearer('Bearer tenant-secret-admin');
    await expect(
      service.registerEndpointSigningCredential(tenantPrincipal, tenant.id, {
        endpointId,
        secretPointer: '/tenant-signing',
      }),
    ).rejects.toMatchObject({ code: 'forbidden' });

    const otherAccount = await service.createAccount({ name: 'external/signing-other', kind: 'external' });
    const otherTenant = await service.createOrAdoptTenant({
      accountId: otherAccount.id,
      name: 'external/signing-other',
      intakeSlug: 'signing-other',
      source: 'api',
      homeVlandscape: 'mew',
    });
    await expect(
      service.registerEndpointSigningCredential(accountAdmin, otherTenant.id, {
        endpointId: '00000000-0000-4000-8000-000000000198',
        secretPointer: '/other-signing',
      }),
    ).rejects.toMatchObject({ code: 'forbidden' });

    const route = await service.upsertRoute(accountAdmin, tenant.id, {
      path: '/webhook/stripe',
      registeredUrl: 'https://hooks.mercury.p.mew.cluster.atomi.cloud/t/signing/webhook/stripe',
      provider: 'stripe',
    });
    const endpoint = await service.upsertEndpoint(accountAdmin, tenant.id, route.id, {
      id: endpointId,
      target: {
        kind: 'coordinate',
        service: 'zinc',
        module: 'checkout',
        canonicalVlandscape: 'mew',
      },
      signingCredentialId: second.id,
    });
    expect(endpoint).toMatchObject({ id: endpointId, signingCredentialId: second.id });
    const third = await service.registerEndpointSigningCredential(accountAdmin, tenant.id, {
      endpointId,
      secretPointer: '/signing-v3',
    });
    expect(third).toMatchObject({ endpointId, generation: 3, status: 'live' });
    expect(await repository.getEndpoint(endpointId)).toMatchObject({ signingCredentialId: third.id });
    expect(await repository.getEndpointSigningCredential(second.id)).toMatchObject({
      status: 'overlap',
      overlapUntil: new Date('2026-07-31T00:00:00.000Z'),
    });
  });

  test('rejects private and rebinding-prone external endpoint destinations', async () => {
    const { repository, service } = harness({
      endpointDestinationResolver: {
        async resolve(hostname) {
          if (hostname === 'mixed.example') return ['93.184.216.34', '10.0.0.1'];
          return ['169.254.169.254'];
        },
      },
    });
    const { account } = await service.provisionDefaultInternalAccount('boot');
    const principal = await service.authenticateBearer('Bearer boot');
    const external = await service.createAccount({ name: 'external/receiver', kind: 'external' });
    const tenant = await service.createOrAdoptTenant({
      accountId: external.id,
      name: 'external/receiver',
      intakeSlug: 'receiver',
      source: 'api',
      homeVlandscape: 'mew',
    });
    const route = await service.upsertRoute(principal, tenant.id, {
      path: '/webhook/stripe',
      registeredUrl: 'https://hooks.mercury.p.mew.cluster.atomi.cloud/t/receiver/webhook/stripe',
      provider: 'stripe',
    });
    await repository.saveEndpointSigningCredential({
      id: 'signing-receiver',
      accountId: external.id,
      tenantId: tenant.id,
      endpointId: 'endpoint-receiver',
      generation: 1,
      secretPointer: '/receiver-signing',
      status: 'live',
      createdAt: new Date(),
    });
    for (const url of [
      'https://127.0.0.1/hooks',
      'https://192.88.99.1/hooks',
      'https://[::ffff:169.254.169.254]/hooks',
      'https://[2001:db8::1]/hooks',
      'https://service.namespace.svc.cluster.local/hooks',
      'https://mixed.example/hooks',
      'https://public.example/hooks',
    ]) {
      await expect(
        service.upsertEndpoint(principal, tenant.id, route.id, {
          id: 'endpoint-receiver',
          target: { kind: 'url', url },
          signingCredentialId: 'signing-receiver',
        }),
      ).rejects.toMatchObject({ code: 'invalid' });
    }
    expect(account.name).toBe('internal/default');
  });

  test('isolates landscape trust records by account and blocks tenant mutation', async () => {
    const { repository, service } = harness();
    const { account: accountA } = await service.provisionDefaultInternalAccount('boot');
    const principalA = await service.authenticateBearer('Bearer boot');
    const accountB = await service.createAccount({ name: 'external/landscape', kind: 'external' });
    await service.issueManagementCredential(accountB.id, undefined, ['landscapes:read', 'landscapes:write'], 'b-token');
    const principalB = await service.authenticateBearer('Bearer b-token');
    await service.saveLandscapeEventSource(principalA, {
      landscape: 'raichu',
      queryUrl: 'https://query-a.example/',
      replayUrl: 'https://replay-a.example/',
      credentialPointer: '/account-a-operations',
      enabled: true,
    });
    await service.saveLandscapeEventSource(principalB, {
      landscape: 'raichu',
      queryUrl: 'https://query-b.example/',
      replayUrl: 'https://replay-b.example/',
      credentialPointer: '/account-b-operations',
      enabled: true,
    });
    expect((await repository.listLandscapeEventSources(accountA.id))[0]?.queryUrl).toContain('query-a');
    expect((await repository.listLandscapeEventSources(accountB.id))[0]?.queryUrl).toContain('query-b');
    const tenantB = await service.createOrAdoptTenant({
      accountId: accountB.id,
      name: 'external/landscape',
      intakeSlug: 'landscape',
      source: 'api',
      homeVlandscape: 'mew',
    });
    await service.issueManagementCredential(accountB.id, tenantB.id, ['landscapes:write'], 'tenant-b-token');
    const tenantPrincipal = await service.authenticateBearer('Bearer tenant-b-token');
    await expect(
      service.saveLandscapeEventSource(tenantPrincipal, {
        landscape: 'ampharos',
        queryUrl: 'https://attacker.example/',
        replayUrl: 'https://attacker.example/',
        credentialPointer: '/attacker',
        enabled: true,
      }),
    ).rejects.toMatchObject({ code: 'forbidden' });
  });

  test('releases expired pending domain claims and enforces route hard caps', async () => {
    const { service, advance } = harness();
    const { account } = await service.provisionDefaultInternalAccount('boot');
    const principal = await service.authenticateBearer('Bearer boot');
    const first = await service.createOrAdoptTenant({
      accountId: account.id,
      name: 'internal/claims-a',
      intakeSlug: 'claims-a',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    const second = await service.createOrAdoptTenant({
      accountId: account.id,
      name: 'internal/claims-b',
      intakeSlug: 'claims-b',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    const claim = await service.registerCustomDomain(principal, first.id, { hostname: 'claim.example' });
    advance(DOMAIN_CLAIM_TTL_SECONDS + 1);
    const replacement = await service.registerCustomDomain(principal, second.id, { hostname: 'claim.example' });
    expect(replacement.domain.id).not.toBe(claim.domain.id);

    for (let index = 0; index < MAX_ROUTES_PER_TENANT; index += 1) {
      await service.upsertRoute(principal, first.id, {
        path: `/webhook/stripe/${index}`,
        registeredUrl: `https://hooks.mercury.p.mew.cluster.atomi.cloud/t/claims-a/webhook/stripe/${index}`,
        provider: 'stripe',
      });
    }
    await expect(
      service.upsertRoute(principal, first.id, {
        path: '/webhook/stripe/overflow',
        registeredUrl: 'https://hooks.mercury.p.mew.cluster.atomi.cloud/t/claims-a/webhook/stripe/overflow',
        provider: 'stripe',
      }),
    ).rejects.toMatchObject({ code: 'conflict' });
  });

  test('deletes only an empty same-account tenant and removes quota and metering state', async () => {
    const { repository, service } = harness();
    const accountA = await service.createAccount({ name: 'external/delete-a', kind: 'external' });
    const accountB = await service.createAccount({ name: 'external/delete-b', kind: 'external' });
    const tenantA = await service.createOrAdoptTenant({
      accountId: accountA.id,
      name: 'external/delete-a',
      intakeSlug: 'delete-a',
      source: 'api',
      homeVlandscape: 'mew',
    });
    const tenantB = await service.createOrAdoptTenant({
      accountId: accountB.id,
      name: 'external/delete-b',
      intakeSlug: 'delete-b',
      source: 'api',
      homeVlandscape: 'mew',
    });
    await service.issueManagementCredential(
      accountA.id,
      undefined,
      ['tenants:write', 'routes:write'],
      'delete-a-token',
    );
    const principalA = await service.authenticateBearer('Bearer delete-a-token');
    await expect(service.deleteTenant(principalA, tenantB.id)).rejects.toMatchObject({ code: 'forbidden' });

    await service.upsertRoute(principalA, tenantA.id, {
      path: '/webhook/stripe',
      registeredUrl: 'https://hooks.mercury.p.mew.cluster.atomi.cloud/t/delete-a/webhook/stripe',
      provider: 'stripe',
    });
    await expect(service.deleteTenant(principalA, tenantA.id)).rejects.toMatchObject({
      code: 'conflict',
      details: { routes: 1 },
    });
    const route = (await repository.listRoutes(tenantA.id))[0];
    if (route === undefined) throw new Error('expected route');
    await service.deleteRoute(principalA, tenantA.id, route.id);
    await service.deleteTenant(principalA, tenantA.id);
    expect(await repository.getTenant(tenantA.id)).toBeUndefined();
    expect(await repository.getQuota(tenantA.id)).toBeUndefined();
    expect(await repository.getMeteringConfiguration(tenantA.id)).toBeUndefined();
  });
});
