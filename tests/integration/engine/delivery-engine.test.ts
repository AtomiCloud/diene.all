import { describe, it } from 'bun:test';
import should from 'should';
import { DeliveryEngine, deliveryEndpointKey } from '../../../src/delivery/engine.ts';
import { ScriptedDeliveryTransport, ScriptedEndpointRefresher } from '../../../src/delivery/fakes.ts';
import {
  type CompiledEndpoint,
  DEDUP_WINDOW_SECONDS,
  type DeliveryJob,
  InternalDeliverySigner,
  type WebhookEnvelope,
} from '../../../src/domain/index.ts';
import { ManualClock, MemorySecretReader, MemoryTelemetry } from '../../../src/runtime/fakes.ts';
import { MemoryLandscapeStore } from '../../../src/storage/memory.ts';

const encoder = new TextEncoder();
const decoder = new TextDecoder();

const endpoint = (id: string, address = `https://${id}.example/webhook`): CompiledEndpoint => ({
  id,
  address,
  addressKind: 'canonical',
  canonicalUrl: address,
  signingSecretRef: 'delivery/secret',
});

const seedEvent = async (
  store: MemoryLandscapeStore,
  clock: ManualClock,
  eventId: string,
  endpoints: readonly CompiledEndpoint[],
  retryWindowMs = 72 * 60 * 60 * 1_000,
): Promise<readonly DeliveryJob[]> => {
  const obligations = endpoints.map(item => ({
    id: `${eventId}:${item.id}`,
    endpointId: item.id,
    address: item.address,
    addressKind: item.addressKind,
    signingSecretRef: item.signingSecretRef,
  }));
  const envelope: WebhookEnvelope = {
    id: eventId,
    tenantId: 'external/acme',
    routeId: 'paid',
    provider: 'stripe',
    landingLandscape: store.landscape,
    receivedAtMs: clock.nowMs(),
    providerTimestampMs: 1_700_000_000_000,
    providerSequence: 'provider-sequence-9',
    providerEventId: `provider-${eventId}`,
    dedupId: `provider-${eventId}`,
    rawBody: encoder.encode(`{"event":"${eventId}"}`),
    headers: {
      'content-type': 'application/json',
      'x-provider-signature': 'must-not-be-forwarded',
    },
    verificationMetadata: { verifier: 'stripe' },
    obligations,
  };
  const jobs: readonly DeliveryJob[] = obligations.map(item => ({
    id: item.id,
    eventId,
    tenantId: envelope.tenantId,
    routeId: envelope.routeId,
    endpointId: item.endpointId,
    address: item.address,
    addressKind: item.addressKind,
    signingSecretRef: item.signingSecretRef,
    createdAtMs: clock.nowMs(),
    dueAtMs: clock.nowMs(),
    retryWindowMs,
    status: 'pending',
    attempts: [],
    misrouteRefreshes: 0,
    replayCount: 0,
  }));
  await (
    await store.acceptOnce({
      dedupKey: `dedup:external%2Facme:paid:${eventId}`,
      dedupTtlSeconds: DEDUP_WINDOW_SECONDS,
      envelope,
      jobs,
    })
  ).unwrap();
  await (await store.acknowledgeEvent(eventId, clock.nowMs())).unwrap();
  return jobs;
};

const createEngine = (
  store: MemoryLandscapeStore,
  clock: ManualClock,
  transport: ScriptedDeliveryTransport,
  refresher = new ScriptedEndpointRefresher(endpoint('refreshed')),
  telemetry = new MemoryTelemetry(),
): DeliveryEngine =>
  new DeliveryEngine(
    store,
    transport,
    new MemorySecretReader({
      'delivery/secret': encoder.encode('secret-value'),
    }),
    refresher,
    clock,
    new InternalDeliverySigner(),
    telemetry,
  );

describe('DeliveryEngine', () => {
  it('should leave a due job untouched when graceful cancellation is already requested', async () => {
    // Arrange
    const clock = new ManualClock(Date.UTC(2026, 0, 1));
    const store = new MemoryLandscapeStore('raichu', clock);
    const jobs = await seedEvent(store, clock, 'event-cancelled', [endpoint('cancelled')]);
    const transport = new ScriptedDeliveryTransport();
    const subject = createEngine(store, clock, transport);
    const controller = new AbortController();
    controller.abort();

    // Act
    const outcome = await (await subject.process(jobs[0]?.id ?? '', { signal: controller.signal })).unwrap();
    const stored = await (await store.getJob(jobs[0]?.id ?? '')).unwrap();

    // Assert
    should(outcome.kind).equal('skipped');
    should(stored?.status).equal('pending');
    should(stored?.attempts).have.length(0);
    should(transport.requests).have.length(0);
  });

  it('should release a cancelled in-flight delivery without recording or scheduling a retry', async () => {
    // Arrange
    const clock = new ManualClock(Date.UTC(2026, 0, 1));
    const store = new MemoryLandscapeStore('raichu', clock);
    const target = endpoint('shutdown');
    const jobs = await seedEvent(store, clock, 'event-shutdown', [target]);
    const originalDueAtMs = jobs[0]?.dueAtMs;
    const transport = new ScriptedDeliveryTransport();
    transport.set(target.address, [
      {
        error: {
          code: 'cancelled',
          message: 'shutdown aborted the request',
        },
      },
    ]);
    const subject = createEngine(store, clock, transport);

    // Act
    const outcome = await (await subject.process(jobs[0]?.id ?? '')).unwrap();
    const stored = await (await store.getJob(jobs[0]?.id ?? '')).unwrap();
    const reclaimed = await (
      await store.claimDueJobs({
        claimToken: 'replacement-supervisor',
        leaseMs: 1_000,
        limit: 1,
        nowMs: clock.nowMs(),
      })
    ).unwrap();

    // Assert
    should(outcome.kind).equal('skipped');
    should(stored?.attempts).have.length(0);
    should(stored?.dueAtMs).equal(originalDueAtMs);
    should(reclaimed).have.length(1);
  });

  it('should isolate endpoints and allow duplicate unordered delivery after an ambiguous failure', async () => {
    // Arrange
    const clock = new ManualClock(Date.UTC(2026, 0, 1));
    const store = new MemoryLandscapeStore('raichu', clock);
    const bad = endpoint('bad');
    const good = endpoint('good');
    const jobs = await seedEvent(store, clock, 'event-isolation', [good, bad]);
    const transport = new ScriptedDeliveryTransport();
    transport.set(bad.address, [
      {
        error: {
          code: 'network',
          message: 'response lost after consumer processed',
        },
      },
      { status: 200 },
    ]);
    transport.set(good.address, [{ status: 200 }]);
    const subject = createEngine(store, clock, transport);

    // Act - deliberately process in the opposite order from registration.
    const badFirst = await (await subject.process(jobs[1]?.id ?? '')).unwrap();
    const goodSecond = await (await subject.process(jobs[0]?.id ?? '')).unwrap();
    clock.advance(5_000);
    const badRetry = await (await subject.process(jobs[1]?.id ?? '')).unwrap();
    const badStored = await (await store.getJob(jobs[1]?.id ?? '')).unwrap();
    const goodStored = await (await store.getJob(jobs[0]?.id ?? '')).unwrap();

    // Assert
    should(badFirst.kind).equal('retry');
    should(goodSecond.kind).equal('completed');
    should(badRetry.kind).equal('completed');
    should(goodStored?.status).equal('completed');
    should(badStored?.status).equal('completed');
    should(transport.requests.map(item => item.url)).deepEqual([bad.address, good.address, bad.address]);
    should(transport.requests.filter(item => item.url === bad.address)).have.length(2);
    should(transport.requests[0]?.headers['x-provider-signature']).be.undefined();
    should(transport.requests[0]?.headers['content-type']).equal('application/vnd.atomi.webhook.v1+json');
    should(transport.requests[0]?.headers['x-atomi-webhook-provider-sequence']).be.undefined();
    const badBodies = transport.requests
      .filter(item => item.url === bad.address)
      .map(
        item =>
          JSON.parse(decoder.decode(item.body)) as {
            readonly dedupId: string;
            readonly delivery: { readonly attempt: number; readonly endpointId: string; readonly replay: boolean };
            readonly payload: { readonly bodyBase64: string; readonly contentType: string };
            readonly providerSequence: string;
            readonly routeId: string;
            readonly tenantId: string;
          },
      );
    should(badBodies.map(item => item.delivery.attempt)).deepEqual([1, 2]);
    should(badBodies.map(item => item.delivery.replay)).deepEqual([false, false]);
    should(badBodies.every(item => item.delivery.endpointId === 'bad')).be.true();
    should(badBodies.every(item => item.tenantId === 'external/acme')).be.true();
    should(badBodies.every(item => item.routeId === 'paid')).be.true();
    should(badBodies.every(item => item.dedupId === 'provider-event-isolation')).be.true();
    should(badBodies.every(item => item.providerSequence === 'provider-sequence-9')).be.true();
    should(badBodies.every(item => item.payload.contentType === 'application/json')).be.true();
    should(
      badBodies.every(
        item => decoder.decode(Buffer.from(item.payload.bodyBase64, 'base64')) === '{"event":"event-isolation"}',
      ),
    ).be.true();
    const badSignatures = transport.requests
      .filter(item => item.url === bad.address)
      .map(item => item.headers['x-atomi-webhook-signature']);
    should(new Set(badSignatures).size).equal(2);
  });

  it('should recompile a 421 address exactly once then use ordinary retry handling', async () => {
    // Arrange
    const clock = new ManualClock(Date.UTC(2026, 0, 1));
    const store = new MemoryLandscapeStore('raichu', clock);
    const original = endpoint('checkout', 'https://old.example/webhook');
    const refreshed = endpoint('checkout', 'https://new.example/webhook');
    const jobs = await seedEvent(store, clock, 'event-421', [original]);
    const transport = new ScriptedDeliveryTransport();
    transport.set(original.address, [{ status: 421 }]);
    transport.set(refreshed.address, [{ status: 421 }, { status: 200 }]);
    const refresher = new ScriptedEndpointRefresher(refreshed);
    const subject = createEngine(store, clock, transport, refresher);

    // Act
    const afterRefresh = await (await subject.process(jobs[0]?.id ?? '')).unwrap();
    clock.advance(5_000);
    const afterOrdinaryRetry = await (await subject.process(jobs[0]?.id ?? '')).unwrap();
    const stored = await (await store.getJob(jobs[0]?.id ?? '')).unwrap();

    // Assert
    should(afterRefresh.kind).equal('retry');
    should(afterOrdinaryRetry.kind).equal('completed');
    should(refresher.requests).have.length(1);
    should(transport.requests.map(item => item.url)).deepEqual([
      original.address,
      refreshed.address,
      refreshed.address,
    ]);
    should(stored?.misrouteRefreshes).equal(1);
    should(stored?.attempts).have.length(3);
    should(new Set(transport.requests.map(item => item.headers['x-atomi-webhook-signature'])).size).equal(3);
  });

  it('should open a per-endpoint circuit after 24 hours and close it on a successful probe or manual action', async () => {
    // Arrange
    const clock = new ManualClock(Date.UTC(2026, 0, 1));
    const store = new MemoryLandscapeStore('raichu', clock);
    const target = endpoint('circuit');
    const firstJobs = await seedEvent(store, clock, 'event-circuit-1', [target]);
    const transport = new ScriptedDeliveryTransport();
    transport.set(target.address, [{ status: 500 }, { status: 500 }, { status: 200 }, { status: 200 }]);
    const subject = createEngine(store, clock, transport);

    // Act
    await subject.process(firstJobs[0]?.id ?? '');
    clock.advance(24 * 60 * 60 * 1_000);
    const openedOutcome = await (await subject.process(firstJobs[0]?.id ?? '')).unwrap();
    const opened = await (await store.getCircuit(deliveryEndpointKey('external/acme', target.id))).unwrap();
    const secondJobs = await seedEvent(store, clock, 'event-circuit-2', [target]);
    const pausedNewEvent = await (await subject.process(secondJobs[0]?.id ?? '')).unwrap();
    const requestsBeforeProbe = transport.requests.length;
    const probe = await (await subject.probe(firstJobs[0]?.id ?? '')).unwrap();
    const closedByProbe = await (await store.getCircuit(deliveryEndpointKey('external/acme', target.id))).unwrap();
    const resumedAfterProbe = await (await store.getJob(secondJobs[0]?.id ?? '')).unwrap();
    await store.setCircuitStatus(deliveryEndpointKey('external/acme', target.id), 'open', clock.nowMs());
    await (await subject.manualClose('external/acme', target.id)).unwrap();
    const closedManually = await (await store.getCircuit(deliveryEndpointKey('external/acme', target.id))).unwrap();

    // Assert
    should(openedOutcome.kind).equal('paused');
    should(opened.status).equal('open');
    should(pausedNewEvent.kind).equal('paused');
    should(transport.requests.length).equal(requestsBeforeProbe + 1);
    should(probe.kind).equal('completed');
    should(closedByProbe.status).equal('closed');
    should(resumedAfterProbe?.status).equal('pending');
    should(closedManually.status).equal('closed');
  });

  it('should select and send exactly one retained endpoint obligation for a management probe', async () => {
    // Arrange
    const clock = new ManualClock(Date.UTC(2026, 0, 1));
    const store = new MemoryLandscapeStore('raichu', clock);
    const target = endpoint('managed-probe');
    const jobs = await seedEvent(store, clock, 'event-managed-probe', [target]);
    await store.setCircuitStatus(deliveryEndpointKey('external/acme', target.id), 'open', clock.nowMs());
    await (await store.pauseJob(jobs[0]?.id ?? '')).unwrap();
    const transport = new ScriptedDeliveryTransport();
    transport.set(target.address, [{ status: 200 }]);
    const subject = createEngine(store, clock, transport);

    // Act
    const succeeded = await (await subject.probeEndpoint('external/acme', target.id)).unwrap();
    const circuit = await (await store.getCircuit(deliveryEndpointKey('external/acme', target.id))).unwrap();

    // Assert
    should(succeeded).be.true();
    should(transport.requests).have.length(1);
    should(circuit.status).equal('closed');
  });

  it('should expire a paused obligation into the DLQ even when its circuit never recovers', async () => {
    // Arrange
    const clock = new ManualClock(Date.UTC(2026, 0, 1));
    const store = new MemoryLandscapeStore('raichu', clock);
    const target = endpoint('permanently-down');
    const jobs = await seedEvent(store, clock, 'event-paused-expiry', [target], 1_000);
    await store.setCircuitStatus(deliveryEndpointKey('external/acme', target.id), 'open', clock.nowMs());
    const transport = new ScriptedDeliveryTransport();
    const telemetry = new MemoryTelemetry();
    const subject = createEngine(store, clock, transport, new ScriptedEndpointRefresher(target), telemetry);
    const paused = await (await subject.process(jobs[0]?.id ?? '')).unwrap();

    // Act
    clock.advance(1_000);
    const outcomes = await subject.runDue(clock.nowMs());
    const stored = await (await store.getJob(jobs[0]?.id ?? '')).unwrap();
    const deadLetters = await (await store.listDeadLetters('external/acme')).unwrap();

    // Assert
    should(paused.kind).equal('paused');
    should(outcomes).have.length(0);
    should(stored?.status).equal('dead-letter');
    should(deadLetters).have.length(1);
    should(deadLetters[0]?.reason).equal('retry-window-expired');
    should(transport.requests).have.length(0);
    should(
      telemetry.events.some(
        event =>
          event.name === 'dlq.enqueued' &&
          event.attributes.tenant === 'external/acme' &&
          event.attributes.endpoint === target.id,
      ),
    ).be.true();
  });

  it('should dead-letter in the landing landscape after 72 hours and support endpoint and event replay', async () => {
    // Arrange
    const clock = new ManualClock(Date.UTC(2026, 0, 1));
    const store = new MemoryLandscapeStore('raichu', clock);
    const first = endpoint('first');
    const second = endpoint('second');
    const jobs = await seedEvent(store, clock, 'event-dlq', [first, second]);
    const transport = new ScriptedDeliveryTransport();
    transport.set(first.address, [{ status: 500 }, { status: 200 }]);
    const subject = createEngine(store, clock, transport);
    await subject.process(jobs[0]?.id ?? '');

    // Act
    clock.advance(72 * 60 * 60 * 1_000);
    const exhausted = await (await subject.process(jobs[0]?.id ?? '')).unwrap();
    const deadLetters = await (await store.listDeadLetters('external/acme')).unwrap();
    const endpointReplay = await (await subject.replayEndpoint('event-dlq', 'first')).unwrap();
    const untouched = await (await store.getJob(jobs[1]?.id ?? '')).unwrap();
    const replayDelivery = await (await subject.process(endpointReplay.id)).unwrap();
    const replayedStored = await (await store.getJob(endpointReplay.id)).unwrap();
    await store.deadLetter(jobs[0]?.id ?? '', clock.nowMs(), 'test');
    await store.deadLetter(jobs[1]?.id ?? '', clock.nowMs(), 'test');
    const eventReplay = await (await subject.replayEvent('event-dlq')).unwrap();

    // Assert
    should(exhausted.kind).equal('dead-letter');
    should(deadLetters).have.length(1);
    should(deadLetters[0]?.landscape).equal('raichu');
    should(endpointReplay.replayCount).equal(1);
    should(untouched?.replayCount).equal(0);
    should(replayDelivery.kind).equal('completed');
    should(replayedStored?.attempts.at(-1)?.replay).be.true();
    const firstEndpointSignatures = transport.requests
      .filter(item => item.url === first.address)
      .map(item => item.headers['x-atomi-webhook-signature']);
    should(new Set(firstEndpointSignatures).size).equal(2);
    should(eventReplay).have.length(2);
    should(eventReplay.every(job => job.status === 'pending')).be.true();
    should(eventReplay.every(job => job.createdAtMs === clock.nowMs())).be.true();
  });
});
