import { describe, expect, test } from 'bun:test';
import { createManagementApi } from '../../../src/http/management/api.ts';
import { InMemoryLandscapeConfigWriter, MercuryConfigurationCompiler } from '../../../src/management/compiler.ts';
import { InMemoryManagementRepository } from '../../../src/management/memory-repository.ts';
import { ManagementService } from '../../../src/management/service.ts';
import type { LandscapeTopology } from '../../../src/management/types.ts';
import { MAX_MANAGEMENT_REQUEST_BYTES, MAX_RETRY_WINDOW_SECONDS } from '../../../src/management/types.ts';

function jsonRequest(path: string, token: string | undefined, body?: unknown, method = 'GET'): Request {
  const headers = new Headers({
    Host: 'forged.customer.example',
    Cookie: 'session=trusted-looking-cookie',
  });
  if (token !== undefined) {
    headers.set('Authorization', `Bearer ${token}`);
  }
  if (body !== undefined) {
    headers.set('Content-Type', 'application/json');
  }
  return new Request(`https://attacker-controlled.example${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

describe('management HTTP API', () => {
  test('is bearer-native and never accepts cookies or Host as identity', async () => {
    const repository = new InMemoryManagementRepository();
    const service = new ManagementService(repository);
    await service.provisionDefaultInternalAccount('native-token');
    const app = createManagementApi(service);

    const unauthenticated = await app.fetch(jsonRequest('/accounts', undefined));
    expect(unauthenticated.status).toBe(401);
    expect(unauthenticated.headers.get('www-authenticate')).toContain('Bearer');

    const authenticated = await app.fetch(jsonRequest('/accounts', 'native-token'));
    expect(authenticated.status).toBe(200);
    const payload = (await authenticated.json()) as {
      accounts: { name: string }[];
    };
    expect(payload.accounts.map(item => item.name)).toEqual(['internal/default']);
  });

  test('supports idempotent T3 tenant adoption and rejects home mutation', async () => {
    const repository = new InMemoryManagementRepository();
    const service = new ManagementService(repository);
    const provisioned = await service.provisionDefaultInternalAccount('native-token');
    const app = createManagementApi(service);
    const input = {
      accountId: provisioned.account.id,
      name: 'internal/nitroso',
      intakeSlug: 'nitroso',
      source: 'cr',
      homeVlandscape: 'mew',
    };
    const created = await app.fetch(jsonRequest('/tenants', 'native-token', input, 'POST'));
    expect(created.status).toBe(201);
    const tenant = (await created.json()) as { id: string };
    const adopted = await app.fetch(jsonRequest('/tenants', 'native-token', input, 'POST'));
    expect(adopted.status).toBe(201);
    expect(((await adopted.json()) as { id: string }).id).toBe(tenant.id);

    const moved = await app.fetch(
      jsonRequest(`/tenants/${tenant.id}`, 'native-token', { homeVlandscape: 'ditto' }, 'PATCH'),
    );
    expect(moved.status).toBe(409);
    expect((await moved.json()) as object).toMatchObject({
      error: 'immutable_home',
    });

    const unavailableReplay = await app.fetch(
      jsonRequest(
        '/replays',
        'native-token',
        {
          tenantId: tenant.id,
          landscape: 'raichu',
          reason: 'operator request',
          scope: { kind: 'event', eventId: 'event-1' },
        },
        'POST',
      ),
    );
    expect(unavailableReplay.status).toBe(503);
    expect(await unavailableReplay.json()).toMatchObject({
      error: 'unavailable',
    });
  });

  test('keeps tenant-bound listing exact even when its credential has wildcard scope', async () => {
    const repository = new InMemoryManagementRepository();
    const service = new ManagementService(repository);
    const { account } = await service.provisionDefaultInternalAccount('account-wide-token');
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
    await service.issueManagementCredential(account.id, first.id, ['tenants:read'], 'tenant-read-token');
    await service.issueManagementCredential(account.id, first.id, ['*'], 'tenant-wildcard-token');
    const app = createManagementApi(service);

    for (const token of ['tenant-read-token', 'tenant-wildcard-token']) {
      const response = await app.fetch(jsonRequest(`/tenants?accountId=${account.id}`, token));
      expect(response.status).toBe(200);
      const payload = (await response.json()) as { tenants: { id: string }[] };
      expect(payload.tenants.map(tenant => tenant.id)).toEqual([first.id]);
    }
    const sibling = await app.fetch(jsonRequest(`/tenants/${second.id}`, 'tenant-wildcard-token'));
    expect(sibling.status).toBe(403);

    const accountWide = await app.fetch(jsonRequest('/tenants', 'account-wide-token'));
    expect(accountWide.status).toBe(200);
    const accountPayload = (await accountWide.json()) as { tenants: { id: string }[] };
    expect(accountPayload.tenants.map(tenant => tenant.id)).toEqual([first.id, second.id]);
  });

  test('exposes health without using a console session', async () => {
    const service = new ManagementService(new InMemoryManagementRepository());
    const response = await createManagementApi(service).fetch(jsonRequest('/health', undefined));
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ repository: 'ok' });
  });

  test('returns the exact two custom-domain CNAME records without secret hashes', async () => {
    const repository = new InMemoryManagementRepository();
    const service = new ManagementService(repository);
    const { account } = await service.provisionDefaultInternalAccount('native-token');
    const tenant = await service.createOrAdoptTenant({
      accountId: account.id,
      name: 'internal/domain-records',
      intakeSlug: 'domain-records',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    const response = await createManagementApi(service).fetch(
      jsonRequest(`/tenants/${tenant.id}/domains`, 'native-token', { hostname: 'Hooks.Customer.Example.' }, 'POST'),
    );
    expect(response.status).toBe(201);
    const registration = (await response.json()) as {
      domain: { id: string; hostname: string; intakeTarget: string; challengeTarget: string };
      records: readonly { type: string; name: string; target: string }[];
      verificationTokenHash?: string;
      verificationToken?: string;
    };
    expect(registration.domain.hostname).toBe('hooks.customer.example');
    expect(registration.records).toEqual([
      {
        type: 'CNAME',
        name: 'hooks.customer.example',
        target: 'hooks.mercury.p.mew.cluster.atomi.cloud',
      },
      {
        type: 'CNAME',
        name: '_acme-challenge.hooks.customer.example',
        target: registration.domain.challengeTarget,
      },
    ]);
    expect(registration.domain.challengeTarget).toBe(
      `mercury-domain-${registration.domain.id}.domain-validation.${registration.domain.intakeTarget}`,
    );
    expect(registration.verificationTokenHash).toBeUndefined();
    expect(registration.verificationToken).toBeUndefined();
    expect(registration.domain).not.toHaveProperty('verificationTokenHash');
    expect(registration.domain).not.toHaveProperty('certificateSecretPointer');
    const callerAssertedSuccess = await createManagementApi(service).fetch(
      jsonRequest(
        `/tenants/${tenant.id}/domains/${registration.domain.id}/verify`,
        'native-token',
        { owned: true, certificateReady: true },
        'POST',
      ),
    );
    expect(callerAssertedSuccess.status).toBe(400);
    expect(await callerAssertedSuccess.json()).toMatchObject({ error: 'invalid' });
  });

  test('compile trigger uses only the trusted local topology and rejects caller topology', async () => {
    const repository = new InMemoryManagementRepository();
    const service = new ManagementService(repository);
    await service.provisionDefaultInternalAccount('native-token');
    const writer = new InMemoryLandscapeConfigWriter();
    const compiler = new MercuryConfigurationCompiler(repository, writer, {
      clock: () => new Date('2026-07-29T00:00:00.000Z'),
    });
    const landscapes = ['raichu'];
    const topology: LandscapeTopology = {
      landscapes,
      services: {},
    };
    const app = createManagementApi(service, {
      compilation: {
        compiler,
        localLandscape: 'raichu',
        topology,
      },
    });

    landscapes[0] = 'hostile';
    const triggered = await app.fetch(jsonRequest('/config/compile', 'native-token', undefined, 'POST'));
    expect(triggered.status).toBe(202);
    expect(await triggered.json()).toMatchObject({
      generation: {
        landscape: 'raichu',
        generation: 1,
        status: 'active',
      },
    });
    expect(writer.currentGeneration('raichu')).toBe(1);
    expect(writer.currentGeneration('hostile')).toBeUndefined();

    const ledger = await app.fetch(jsonRequest('/config/generations?landscape=raichu', 'native-token'));
    expect(ledger.status).toBe(200);
    expect(await ledger.json()).toMatchObject({
      generations: [{ landscape: 'raichu', generation: 1 }],
      acknowledgements: [{ landscape: 'raichu', generation: 1 }],
    });
    const otherLedger = await app.fetch(jsonRequest('/config/generations?landscape=ampharos', 'native-token'));
    expect(await otherLedger.json()).toEqual({
      generations: [],
      acknowledgements: [],
    });
    const health = await app.fetch(jsonRequest('/health', undefined));
    expect(await health.json()).toMatchObject({
      activeGenerations: [{ landscape: 'raichu', generation: 1 }],
    });

    const hostile = await app.fetch(
      jsonRequest('/config/compile', 'native-token', { landscapes: ['hostile'], services: {} }, 'POST'),
    );
    expect(hostile.status).toBe(400);
    expect(await hostile.json()).toMatchObject({ error: 'invalid' });
    expect(await repository.listConfigGenerations()).toHaveLength(1);
  });

  test('rejects a non-local trusted compiler topology during construction', () => {
    const repository = new InMemoryManagementRepository();
    const service = new ManagementService(repository);
    const compiler = new MercuryConfigurationCompiler(repository, new InMemoryLandscapeConfigWriter());
    expect(() =>
      createManagementApi(service, {
        compilation: {
          compiler,
          localLandscape: 'raichu',
          topology: {
            landscapes: ['raichu', 'ampharos'],
            services: {},
          },
        },
      }),
    ).toThrow('exactly the configured local landscape');
  });

  test('rejects raw secret-pointer inputs, oversized bodies, and management rate excess', async () => {
    const repository = new InMemoryManagementRepository();
    const service = new ManagementService(repository, {
      clock: () => new Date('2026-07-29T00:00:00.000Z'),
    });
    const { account } = await service.provisionDefaultInternalAccount('native-token');
    const tenant = await service.createOrAdoptTenant({
      accountId: account.id,
      name: 'internal/limited',
      intakeSlug: 'limited',
      source: 'cr',
      homeVlandscape: 'mew',
      quota: {
        intakeRps: 10,
        burst: 20,
        managementRps: 1,
        retryWindowSeconds: MAX_RETRY_WINDOW_SECONDS,
        dedupWindowSeconds: MAX_RETRY_WINDOW_SECONDS,
        retentionMonths: 2,
      },
    });
    await service.issueManagementCredential(account.id, tenant.id, ['accounts:read'], 'limited-token');
    const app = createManagementApi(service);

    const rawPointer = await app.fetch(
      jsonRequest(
        `/tenants/${tenant.id}/provider-credentials`,
        'native-token',
        { provider: 'stripe', secretPointer: '/another-tenant/stripe' },
        'POST',
      ),
    );
    expect(rawPointer.status).toBe(400);

    const oversized = await app.fetch(
      jsonRequest(
        '/accounts',
        'native-token',
        { name: `external/${'x'.repeat(MAX_MANAGEMENT_REQUEST_BYTES)}` },
        'POST',
      ),
    );
    expect(oversized.status).toBe(400);

    expect((await app.fetch(jsonRequest('/accounts', 'limited-token'))).status).toBe(200);
    expect((await app.fetch(jsonRequest('/accounts', 'limited-token'))).status).toBe(429);
  });

  test('cancels a chunked management body as soon as its byte cap is crossed', async () => {
    const service = new ManagementService(new InMemoryManagementRepository());
    await service.provisionDefaultInternalAccount('native-token');
    let cancelled = false;
    const body = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new Uint8Array(MAX_MANAGEMENT_REQUEST_BYTES));
        controller.enqueue(Uint8Array.of(1));
      },
      cancel() {
        cancelled = true;
      },
    });
    const init: RequestInit & { readonly duplex: 'half' } = {
      method: 'POST',
      headers: {
        Authorization: 'Bearer native-token',
        'Content-Type': 'application/json',
      },
      body,
      duplex: 'half',
    };
    const response = await createManagementApi(service).fetch(new Request('https://management.example/accounts', init));
    expect(response.status).toBe(400);
    expect(cancelled).toBe(true);
    expect(await response.json()).toMatchObject({ error: 'invalid' });
  });

  test('keeps endpoint secret provisioning admin-only, flat, opaque, and usable before endpoint creation', async () => {
    const repository = new InMemoryManagementRepository();
    const service = new ManagementService(repository, {
      clock: () => new Date('2026-07-29T00:00:00.000Z'),
    });
    const { account } = await service.provisionDefaultInternalAccount('native-token');
    const principal = await service.authenticateBearer('Bearer native-token');
    const tenant = await service.createOrAdoptTenant({
      accountId: account.id,
      name: 'internal/signing-api',
      intakeSlug: 'signing-api',
      source: 'cr',
      homeVlandscape: 'mew',
    });
    const route = await service.upsertRoute(principal, tenant.id, {
      path: '/webhook/stripe',
      registeredUrl: 'https://hooks.mercury.p.mew.cluster.atomi.cloud/t/signing-api/webhook/stripe',
      provider: 'stripe',
    });
    await service.issueManagementCredential(account.id, tenant.id, ['secrets:provision'], 'tenant-token');
    const app = createManagementApi(service);
    const endpointId = '00000000-0000-4000-8000-000000000098';
    const providerPath = `/admin/tenants/${tenant.id}/provider-credentials`;
    const adminPath = `/admin/tenants/${tenant.id}/endpoint-signing-credentials`;

    expect(
      (
        await app.fetch(
          jsonRequest(providerPath, 'tenant-token', { provider: 'stripe', secretPointer: '/stripe-v1' }, 'POST'),
        )
      ).status,
    ).toBe(403);
    expect(
      (
        await app.fetch(
          jsonRequest(providerPath, 'native-token', { provider: 'stripe', secretPointer: '/stripe/v1' }, 'POST'),
        )
      ).status,
    ).toBe(400);
    const providerProvisioned = await app.fetch(
      jsonRequest(providerPath, 'native-token', { provider: 'stripe', secretPointer: '/stripe-v1' }, 'POST'),
    );
    expect(providerProvisioned.status).toBe(201);
    const providerCredential = (await providerProvisioned.json()) as { id: string; secretPointer?: string };
    expect(providerCredential.secretPointer).toBeUndefined();
    const providerSelection = await app.fetch(
      jsonRequest(
        `/tenants/${tenant.id}/provider-credentials`,
        'native-token',
        { credentialId: providerCredential.id },
        'POST',
      ),
    );
    expect(providerSelection.status).toBe(200);
    expect(await providerSelection.json()).not.toHaveProperty('secretPointer');
    const providerPointerInjection = await app.fetch(
      jsonRequest(
        `/tenants/${tenant.id}/provider-credentials`,
        'native-token',
        { credentialId: providerCredential.id, secretPointer: '/ignored-raw-pointer' },
        'POST',
      ),
    );
    expect(providerPointerInjection.status).toBe(400);

    const tenantProvision = await app.fetch(
      jsonRequest(adminPath, 'tenant-token', { endpointId, secretPointer: '/signing-v1' }, 'POST'),
    );
    expect(tenantProvision.status).toBe(403);
    const hierarchical = await app.fetch(
      jsonRequest(adminPath, 'native-token', { endpointId, secretPointer: '/signing/v1' }, 'POST'),
    );
    expect(hierarchical.status).toBe(400);
    const provisioned = await app.fetch(
      jsonRequest(adminPath, 'native-token', { endpointId, secretPointer: '/signing-v1' }, 'POST'),
    );
    expect(provisioned.status).toBe(201);
    const credential = (await provisioned.json()) as { id: string; secretPointer?: string };
    expect(credential.secretPointer).toBeUndefined();

    const rawTenantPointer = await app.fetch(
      jsonRequest(
        `/tenants/${tenant.id}/routes/${route.id}/endpoints`,
        'native-token',
        {
          id: endpointId,
          target: {
            kind: 'coordinate',
            service: 'zinc',
            module: 'checkout',
            canonicalVlandscape: 'mew',
          },
          signingCredentialId: credential.id,
          signingSecretPointer: '/ignored-raw-pointer',
        },
        'POST',
      ),
    );
    expect(rawTenantPointer.status).toBe(400);
    const created = await app.fetch(
      jsonRequest(
        `/tenants/${tenant.id}/routes/${route.id}/endpoints`,
        'native-token',
        {
          id: endpointId,
          target: {
            kind: 'coordinate',
            service: 'zinc',
            module: 'checkout',
            canonicalVlandscape: 'mew',
          },
          signingCredentialId: credential.id,
        },
        'POST',
      ),
    );
    expect(created.status).toBe(201);
    const rotated = await app.fetch(
      jsonRequest(adminPath, 'native-token', { endpointId, secretPointer: '/signing-v2' }, 'POST'),
    );
    expect(rotated.status).toBe(201);
    const rotatedCredential = (await rotated.json()) as { id: string; secretPointer?: string };
    expect(rotatedCredential.secretPointer).toBeUndefined();
    expect(await repository.getEndpoint(endpointId)).toMatchObject({
      signingCredentialId: rotatedCredential.id,
    });
    expect(await repository.getEndpointSigningCredential(credential.id)).toMatchObject({
      status: 'overlap',
      overlapUntil: new Date('2026-07-31T00:00:00.000Z'),
    });

    const routes = await app.fetch(jsonRequest(`/tenants/${tenant.id}/routes`, 'native-token'));
    expect(routes.status).toBe(200);
    expect(await routes.json()).toMatchObject({
      routes: [{ endpoints: [{ id: endpointId, signingCredentialId: rotatedCredential.id }] }],
    });
  });
});
