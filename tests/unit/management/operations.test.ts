import { describe, expect, test } from 'bun:test';
import { InMemoryManagementRepository } from '../../../src/management/memory-repository.ts';
import {
  type CircuitCommander,
  ManagementService,
  type ManagementServiceOptions,
  type ReplayDispatcher,
} from '../../../src/management/service.ts';

async function operationsHarness(options: ManagementServiceOptions = {}) {
  let id = 0;
  const repository = new InMemoryManagementRepository();
  const service = new ManagementService(repository, {
    ...options,
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
  await service.saveLandscapeEventSource(principal, {
    landscape: 'raichu',
    queryUrl: 'https://events.raichu.example/query',
    replayUrl: 'https://events.raichu.example/replay',
    credentialPointer: '/mercury-raichu-operations',
    enabled: true,
  });
  const route = await service.upsertRoute(principal, tenant.id, {
    path: '/webhook/stripe',
    registeredUrl: 'https://hooks.mercury.p.mew.cluster.atomi.cloud/t/nitroso/webhook/stripe',
    provider: 'stripe',
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
  await repository.saveEndpoint({
    ...endpoint,
    circuitState: 'open',
    circuitOpenedAt: new Date('2026-07-28T00:00:00.000Z'),
  });
  return { endpoint, principal, repository, service, tenant };
}

describe('management operational dependencies', () => {
  test('fails closed without dispatcher or commander and records no false success', async () => {
    const { endpoint, principal, repository, service, tenant } = await operationsHarness();
    await expect(
      service.requestReplay(principal, {
        tenantId: tenant.id,
        landscape: 'raichu',
        scope: { kind: 'event', eventId: 'event-1' },
        reason: 'operator request',
      }),
    ).rejects.toMatchObject({ code: 'unavailable' });
    expect(await repository.listReplayAudits(tenant.id)).toHaveLength(0);

    await expect(
      service.reenableCircuit(principal, {
        tenantId: tenant.id,
        landscape: 'raichu',
        endpointId: endpoint.id,
      }),
    ).rejects.toMatchObject({ code: 'unavailable' });
    await expect(
      service.probeCircuit(principal, {
        tenantId: tenant.id,
        landscape: 'raichu',
        endpointId: endpoint.id,
      }),
    ).rejects.toMatchObject({ code: 'unavailable' });
    expect((await repository.getEndpoint(endpoint.id))?.circuitState).toBe('open');
  });

  test('preserves replay audit before a failing dispatch and leaves circuit state unchanged on command failure', async () => {
    const replayDispatcher: ReplayDispatcher = {
      async dispatch() {
        throw new Error('replay transport down');
      },
    };
    const circuitCommander: CircuitCommander = {
      async reenable() {
        throw new Error('circuit transport down');
      },
      async probe() {
        throw new Error('probe transport down');
      },
    };
    const { endpoint, principal, repository, service, tenant } = await operationsHarness({
      replayDispatcher,
      circuitCommander,
    });

    await expect(
      service.requestReplay(principal, {
        tenantId: tenant.id,
        landscape: 'raichu',
        scope: { kind: 'event', eventId: 'event-1' },
        reason: 'operator request',
      }),
    ).rejects.toMatchObject({
      code: 'unavailable',
      details: { cause: 'replay transport down' },
    });
    expect(await repository.listReplayAudits(tenant.id)).toHaveLength(1);

    await expect(
      service.reenableCircuit(principal, {
        tenantId: tenant.id,
        landscape: 'raichu',
        endpointId: endpoint.id,
      }),
    ).rejects.toMatchObject({ code: 'unavailable' });
    await expect(
      service.probeCircuit(principal, {
        tenantId: tenant.id,
        landscape: 'raichu',
        endpointId: endpoint.id,
      }),
    ).rejects.toMatchObject({ code: 'unavailable' });
    expect((await repository.getEndpoint(endpoint.id))?.circuitState).toBe('open');
  });

  test('dispatches only after audit and applies successful circuit commands', async () => {
    const repository = new InMemoryManagementRepository();
    let observedAuditCount = 0;
    let probeSucceeded = false;
    const replayDispatcher: ReplayDispatcher = {
      async dispatch(input) {
        observedAuditCount = (await repository.listReplayAudits(input.tenantId)).length;
      },
    };
    const circuitCommander: CircuitCommander = {
      async reenable() {},
      async probe() {
        return probeSucceeded;
      },
    };
    let id = 0;
    const service = new ManagementService(repository, {
      replayDispatcher,
      circuitCommander,
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
    await service.saveLandscapeEventSource(principal, {
      landscape: 'raichu',
      queryUrl: 'https://events.raichu.example/query',
      replayUrl: 'https://events.raichu.example/replay',
      credentialPointer: '/mercury-raichu-operations',
      enabled: true,
    });
    const route = await service.upsertRoute(principal, tenant.id, {
      path: '/webhook/stripe',
      registeredUrl: 'https://hooks.mercury.p.mew.cluster.atomi.cloud/t/nitroso/webhook/stripe',
      provider: 'stripe',
    });
    await repository.saveEndpointSigningCredential({
      id: '00000000-0000-4000-8000-000000000199',
      accountId: provisioned.account.id,
      tenantId: tenant.id,
      endpointId: '00000000-0000-4000-8000-000000000198',
      generation: 1,
      secretPointer: '/mew-signing',
      status: 'live',
      createdAt: new Date('2026-07-29T00:00:00.000Z'),
    });
    const endpoint = await service.upsertEndpoint(principal, tenant.id, route.id, {
      id: '00000000-0000-4000-8000-000000000198',
      target: {
        kind: 'coordinate',
        service: 'zinc',
        module: 'checkout',
        canonicalVlandscape: 'mew',
      },
      signingCredentialId: '00000000-0000-4000-8000-000000000199',
    });

    await service.requestReplay(principal, {
      tenantId: tenant.id,
      landscape: 'raichu',
      scope: { kind: 'event', eventId: 'event-1' },
      reason: 'operator request',
    });
    expect(observedAuditCount).toBe(1);

    const negativeProbe = await service.probeCircuit(principal, {
      tenantId: tenant.id,
      landscape: 'raichu',
      endpointId: endpoint.id,
    });
    expect(negativeProbe.succeeded).toBe(false);
    expect(negativeProbe.endpoint.circuitState).toBe('open');

    await service.reenableCircuit(principal, {
      tenantId: tenant.id,
      landscape: 'raichu',
      endpointId: endpoint.id,
    });
    expect((await repository.getEndpoint(endpoint.id))?.circuitState).toBe('closed');

    probeSucceeded = true;
    const positiveProbe = await service.probeCircuit(principal, {
      tenantId: tenant.id,
      landscape: 'raichu',
      endpointId: endpoint.id,
    });
    expect(positiveProbe.succeeded).toBe(true);
    expect(positiveProbe.endpoint.circuitState).toBe('closed');
  });
});
