import { describe, it } from 'bun:test';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import should from 'should';
import { DeliveryEngine, deliveryEndpointKey } from '../../../src/delivery/engine.ts';
import { ScriptedDeliveryTransport, ScriptedEndpointRefresher } from '../../../src/delivery/fakes.ts';
import {
  DEDUP_WINDOW_SECONDS,
  type DeliveryJob,
  InternalDeliverySigner,
  type LandscapeRuntimeConfig,
  type WebhookEnvelope,
} from '../../../src/domain/index.ts';
import {
  createLandscapeOperationsApi,
  type LandscapeAuthenticationFailure,
  type LandscapeOperationsAuthenticator,
  type LandscapeOperationsAuthorization,
} from '../../../src/http/landscape/api.ts';
import {
  ManualClock,
  MemorySecretReader,
  MemoryTelemetry,
  SequenceIdentifierFactory,
} from '../../../src/runtime/fakes.ts';
import { EventRetentionManager, MemoryArchiveStore } from '../../../src/storage/archive.ts';
import { MemoryLandscapeStore } from '../../../src/storage/memory.ts';

const encoder = new TextEncoder();

class HeaderAuthenticator implements LandscapeOperationsAuthenticator {
  public authorization: LandscapeOperationsAuthorization = {
    subject: 'console-user',
    accountId: 'account-acme',
    tenants: ['external/acme'],
    capabilities: ['operations:read', 'events:replay', 'endpoints:replay', 'endpoints:reenable', 'retention:run'],
  };
  public unavailable = false;
  public throws = false;

  async authenticate(
    request: Request,
  ): Promise<Result<LandscapeOperationsAuthorization, LandscapeAuthenticationFailure>> {
    if (this.throws) {
      throw new Error('authentication dependency failed');
    }
    if (this.unavailable) {
      return Err({
        code: 'unavailable',
        message: 'authentication dependency failed',
      });
    }
    return request.headers.get('authorization') === 'Bearer good'
      ? Ok(this.authorization)
      : Err({ code: 'invalid', message: 'invalid credential' });
  }
}

const seedEvent = async (
  store: MemoryLandscapeStore,
  clock: ManualClock,
  tenantId: string,
  eventId: string,
  endpointId: string,
  receivedAtMs = clock.nowMs(),
): Promise<DeliveryJob> => {
  const jobId = `${eventId}:${endpointId}`;
  const envelope: WebhookEnvelope = {
    id: eventId,
    tenantId,
    routeId: 'paid',
    provider: 'stripe',
    landingLandscape: store.landscape,
    receivedAtMs,
    providerEventId: `provider-${eventId}`,
    dedupId: `provider-${eventId}`,
    rawBody: encoder.encode(`{"event":"${eventId}"}`),
    headers: {
      'content-type': 'application/json',
      'x-provider-signature': 'provider-only',
    },
    verificationMetadata: { verified: 'true' },
    obligations: [
      {
        id: jobId,
        endpointId,
        address: `https://${endpointId}.example/webhook`,
        addressKind: 'external',
        signingSecretRef: 'delivery/secret',
      },
    ],
  };
  const job: DeliveryJob = {
    id: jobId,
    eventId,
    tenantId,
    routeId: envelope.routeId,
    endpointId,
    address: `https://${endpointId}.example/webhook`,
    addressKind: 'external',
    signingSecretRef: 'delivery/secret',
    createdAtMs: receivedAtMs,
    dueAtMs: receivedAtMs,
    retryWindowMs: 72 * 60 * 60 * 1_000,
    status: 'pending',
    attempts: [],
    misrouteRefreshes: 0,
    replayCount: 0,
  };
  await (
    await store.acceptOnce({
      dedupKey: `dedup:${encodeURIComponent(tenantId)}:paid:${eventId}`,
      dedupTtlSeconds: DEDUP_WINDOW_SECONDS,
      envelope,
      jobs: [job],
    })
  ).unwrap();
  await (await store.acknowledgeEvent(eventId, receivedAtMs)).unwrap();
  return job;
};

const createHarness = async () => {
  const clock = new ManualClock(Date.UTC(2026, 6, 1));
  const store = new MemoryLandscapeStore('raichu', clock);
  const active: LandscapeRuntimeConfig = {
    generation: 1,
    landscape: 'raichu',
    compiledAtMs: clock.nowMs(),
    sourceRevision: 'revision-1',
    tenants: [],
  };
  await (await store.stage(active)).unwrap();
  await (await store.activate(1, null)).unwrap();
  const transport = new ScriptedDeliveryTransport();
  const delivery = new DeliveryEngine(
    store,
    transport,
    new MemorySecretReader({
      'delivery/secret': encoder.encode('secret-value'),
    }),
    new ScriptedEndpointRefresher({
      id: 'refreshed',
      address: 'https://refreshed.example/webhook',
      addressKind: 'external',
      canonicalUrl: 'https://refreshed.example/webhook',
      signingSecretRef: 'delivery/secret',
    }),
    clock,
    new InternalDeliverySigner(),
    new MemoryTelemetry(),
  );
  const authenticator = new HeaderAuthenticator();
  const supervisor = { running: true };
  const archive = new MemoryArchiveStore();
  const retention = new EventRetentionManager(store, archive, clock, new MemoryTelemetry());
  const app = createLandscapeOperationsApi({
    flow: store,
    delivery,
    config: store,
    authenticator,
    clock,
    identifiers: new SequenceIdentifierFactory(['action-1', 'action-2', 'action-3', 'action-4']),
    retention: { run: tenantId => retention.rollover(tenantId) },
    supervisor,
  });
  return { app, archive, authenticator, clock, delivery, retention, store, supervisor };
};

const authorizedHeaders = { authorization: 'Bearer good' };
const audit = {
  requestId: 'request-123',
  sessionId: 'session-123',
  accountId: 'account-acme',
  reason: 'Receiver recovered after incident.',
};

describe('local landscape operations API', () => {
  it('should fail closed for missing, unavailable, and tenant-out-of-scope authorization', async () => {
    // Arrange
    const harness = await createHarness();
    await seedEvent(harness.store, harness.clock, 'external/acme', 'event-auth', 'endpoint-a');

    // Act
    const missing = await harness.app.request('/health');
    harness.authenticator.unavailable = true;
    const unavailable = await harness.app.request('/health', {
      headers: authorizedHeaders,
    });
    harness.authenticator.unavailable = false;
    harness.authenticator.authorization = {
      ...harness.authenticator.authorization,
      tenants: ['external/other'],
    };
    const forbidden = await harness.app.request('/tenants/external%2Facme/events', { headers: authorizedHeaders });
    harness.authenticator.authorization = {
      ...harness.authenticator.authorization,
      tenants: '*',
    };
    const testControl = await harness.app.request('/__test/reset', {
      headers: authorizedHeaders,
    });

    // Assert
    should(missing.status).equal(401);
    should(unavailable.status).equal(503);
    should(forbidden.status).equal(403);
    should(testControl.status).equal(404);
  });

  it('should expose health, filtered retained events, event jobs, and the tenant DLQ without secret material', async () => {
    // Arrange
    const harness = await createHarness();
    const acmeJob = await seedEvent(harness.store, harness.clock, 'external/acme', 'event-acme', 'endpoint-a');
    await seedEvent(harness.store, harness.clock, 'external/other', 'event-other', 'endpoint-other');
    await (await harness.store.deadLetter(acmeJob.id, harness.clock.nowMs(), 'retry window exhausted')).unwrap();

    // Act
    const health = await harness.app.request('/health', {
      headers: authorizedHeaders,
    });
    const list = await harness.app.request(
      '/tenants/external%2Facme/events?provider=stripe&endpointId=endpoint-a&status=dead-letter',
      { headers: authorizedHeaders },
    );
    const detail = await harness.app.request('/tenants/external%2Facme/events/event-acme', {
      headers: authorizedHeaders,
    });
    const dlq = await harness.app.request('/tenants/external%2Facme/dlq', {
      headers: authorizedHeaders,
    });
    const listBody = (await list.json()) as { items: Array<{ id: string }> };
    const detailBody = await detail.json();
    const dlqBody = (await dlq.json()) as { items: Array<{ eventId: string }> };

    // Assert
    should(health.status).equal(200);
    should(((await health.json()) as { status: string }).status).equal('healthy');
    should(list.status).equal(200);
    should(listBody.items.map(item => item.id)).deepEqual(['event-acme']);
    should(detail.status).equal(200);
    should(JSON.stringify(detailBody)).containEql(Buffer.from('{"event":"event-acme"}').toString('base64'));
    should(JSON.stringify(detailBody)).not.containEql('signingSecretRef');
    should(JSON.stringify(detailBody)).not.containEql('secret-value');
    should(JSON.stringify(detailBody)).not.containEql('provider-only');
    should(dlq.status).equal(200);
    should(dlqBody.items.map(item => item.eventId)).deepEqual(['event-acme']);
  });

  it('should replay by event or endpoint and manually re-enable only the authorized tenant circuit', async () => {
    // Arrange
    const harness = await createHarness();
    const first = await seedEvent(harness.store, harness.clock, 'external/acme', 'event-first', 'endpoint-a');
    const second = await seedEvent(harness.store, harness.clock, 'external/acme', 'event-second', 'endpoint-a');
    const paused = await seedEvent(harness.store, harness.clock, 'external/acme', 'event-paused', 'endpoint-b');
    await (await harness.store.deadLetter(first.id, harness.clock.nowMs(), 'exhausted')).unwrap();
    await (await harness.store.deadLetter(second.id, harness.clock.nowMs(), 'exhausted')).unwrap();
    await (await harness.store.pauseJob(paused.id)).unwrap();
    await (
      await harness.store.setCircuitStatus(
        deliveryEndpointKey('external/acme', 'endpoint-b'),
        'open',
        harness.clock.nowMs(),
      )
    ).unwrap();

    // Act
    const endpointReplay = await harness.app.request('/tenants/external%2Facme/endpoints/endpoint-a/replay', {
      method: 'POST',
      headers: { ...authorizedHeaders, 'content-type': 'application/json' },
      body: JSON.stringify({ audit }),
    });
    const eventReplay = await harness.app.request('/tenants/external%2Facme/events/event-first/replay', {
      method: 'POST',
      headers: { ...authorizedHeaders, 'content-type': 'application/json' },
      body: JSON.stringify({ endpointId: 'endpoint-a', audit }),
    });
    const badAudit = await harness.app.request('/tenants/external%2Facme/events/event-first/replay', {
      method: 'POST',
      headers: { ...authorizedHeaders, 'content-type': 'application/json' },
      body: JSON.stringify({
        audit: { ...audit, accountId: 'other-account' },
      }),
    });
    const reenabled = await harness.app.request('/tenants/external%2Facme/endpoints/endpoint-b/circuit/re-enable', {
      method: 'POST',
      headers: { ...authorizedHeaders, 'content-type': 'application/json' },
      body: JSON.stringify({ audit }),
    });
    const endpointReplayBody = (await endpointReplay.json()) as {
      affectedCount: number;
    };
    const firstStored = await (await harness.store.getJob(first.id)).unwrap();
    const secondStored = await (await harness.store.getJob(second.id)).unwrap();
    const pausedStored = await (await harness.store.getJob(paused.id)).unwrap();
    const circuit = await (await harness.store.getCircuit(deliveryEndpointKey('external/acme', 'endpoint-b'))).unwrap();

    // Assert
    should(endpointReplay.status).equal(202);
    should(endpointReplayBody.affectedCount).equal(2);
    should(eventReplay.status).equal(202);
    should(badAudit.status).equal(400);
    should(reenabled.status).equal(202);
    should(firstStored?.status).equal('pending');
    should(firstStored?.replayCount).equal(2);
    should(secondStored?.replayCount).equal(1);
    should(pausedStored?.status).equal('pending');
    should(circuit.status).equal('closed');
  });

  it('should run the composed retention manager only with tenant-scoped retention authority and never fake success', async () => {
    // Arrange
    const successful = await createHarness();
    const oldJob = await seedEvent(
      successful.store,
      successful.clock,
      'external/acme',
      'event-archive',
      'endpoint-a',
      Date.UTC(2026, 0, 15),
    );
    await (await successful.store.completeJob(oldJob.id)).unwrap();

    // Act
    const archived = await successful.app.request('/tenants/external%2Facme/maintenance/retention', {
      method: 'POST',
      headers: { ...authorizedHeaders, 'content-type': 'application/json' },
      body: JSON.stringify({ audit }),
    });
    const archivedBody = (await archived.json()) as {
      archivedMonths: string[];
      liveMonths: string[];
    };
    const removedEvent = await (await successful.store.getEvent('event-archive')).unwrap();

    const failing = await createHarness();
    const failedJob = await seedEvent(
      failing.store,
      failing.clock,
      'external/acme',
      'event-retained-on-failure',
      'endpoint-a',
      Date.UTC(2026, 1, 15),
    );
    await (await failing.store.completeJob(failedJob.id)).unwrap();
    failing.authenticator.authorization = {
      ...failing.authenticator.authorization,
      capabilities: ['operations:read'],
    };
    const forbidden = await failing.app.request('/tenants/external%2Facme/maintenance/retention', {
      method: 'POST',
      headers: { ...authorizedHeaders, 'content-type': 'application/json' },
      body: JSON.stringify({ audit }),
    });
    failing.authenticator.authorization = {
      ...failing.authenticator.authorization,
      capabilities: ['operations:read', 'retention:run'],
    };
    failing.archive.failingMonths.add('2026-02');
    const unavailable = await failing.app.request('/tenants/external%2Facme/maintenance/retention', {
      method: 'POST',
      headers: { ...authorizedHeaders, 'content-type': 'application/json' },
      body: JSON.stringify({ audit }),
    });
    const preservedEvent = await (await failing.store.getEvent('event-retained-on-failure')).unwrap();

    // Assert
    should(archived.status).equal(200);
    should(archivedBody.archivedMonths).deepEqual(['2026-01']);
    should(archivedBody.liveMonths).deepEqual([]);
    should(removedEvent).be.null();
    should(successful.archive.objects.has('raichu:external/acme:2026-01/versions/1/parts/00000000')).be.true();
    should(successful.archive.objects.has('raichu:external/acme:2026-01/versions/1/manifest')).be.true();
    should(forbidden.status).equal(403);
    should(unavailable.status).equal(503);
    should(preservedEvent?.id).equal('event-retained-on-failure');
  });
});
