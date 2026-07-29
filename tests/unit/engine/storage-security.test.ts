import { describe, it } from 'bun:test';
import should from 'should';
import { type AtomicAcceptRequest, DEDUP_WINDOW_SECONDS } from '../../../src/domain/index.ts';
import { ManualClock } from '../../../src/runtime/fakes.ts';
import { MemoryLandscapeStore } from '../../../src/storage/memory.ts';

const encoder = new TextEncoder();
const tenantId = 'external/acme';

const atomicRequestForEndpoint = (eventId: string, endpointId: string, receivedAtMs: number): AtomicAcceptRequest => {
  const jobId = `${eventId}:${endpointId}`;
  return {
    dedupKey: `dedup:external%2Facme:paid:${eventId}`,
    dedupTtlSeconds: DEDUP_WINDOW_SECONDS,
    envelope: {
      id: eventId,
      tenantId,
      routeId: 'paid',
      provider: 'stripe',
      landingLandscape: 'raichu',
      receivedAtMs,
      providerEventId: eventId,
      dedupId: eventId,
      rawBody: encoder.encode(`{"id":"${eventId}"}`),
      headers: { 'content-type': 'application/json' },
      verificationMetadata: {},
      obligations: [
        {
          id: jobId,
          endpointId,
          address: 'https://receiver.example/webhook',
          addressKind: 'canonical',
          signingSecretRef: 'delivery/acme',
        },
      ],
    },
    jobs: [
      {
        id: jobId,
        eventId,
        tenantId,
        routeId: 'paid',
        endpointId,
        address: 'https://receiver.example/webhook',
        addressKind: 'canonical',
        signingSecretRef: 'delivery/acme',
        createdAtMs: receivedAtMs,
        dueAtMs: receivedAtMs,
        retryWindowMs: 72 * 60 * 60 * 1_000,
        status: 'pending',
        attempts: [],
        misrouteRefreshes: 0,
        replayCount: 0,
      },
    ],
  };
};

const seedDeadLetters = async (store: MemoryLandscapeStore, inputs: readonly AtomicAcceptRequest[]): Promise<void> => {
  for (const input of inputs) {
    await (await store.acceptOnce(input)).unwrap();
    await (
      await store.deadLetter(input.jobs[0]?.id ?? '', input.envelope.receivedAtMs, `exhausted-${input.envelope.id}`)
    ).unwrap();
  }
};

describe('MemoryLandscapeStore security parity', () => {
  it('should drain more than one endpoint replay page despite unrelated tenant dead letters', async () => {
    // Arrange
    const nowMs = Date.UTC(2026, 0, 1);
    const clock = new ManualClock(nowMs);
    const subject = new MemoryLandscapeStore('raichu', clock);
    const targetEndpointId = 'endpoint-target';
    const noiseEndpointId = 'endpoint-noise';
    const targetInputs = Array.from({ length: 101 }, (_, index) =>
      atomicRequestForEndpoint(`event-target-${String(index).padStart(4, '0')}`, targetEndpointId, nowMs + index),
    );
    const noiseInputs = Array.from({ length: 1_001 }, (_, index) =>
      atomicRequestForEndpoint(`event-noise-${String(index).padStart(4, '0')}`, noiseEndpointId, nowMs + index),
    );
    await seedDeadLetters(subject, targetInputs);
    await seedDeadLetters(subject, noiseInputs);

    // Act
    const first = await (
      await subject.replayDeadLettersForEndpoint(tenantId, targetEndpointId, nowMs + 2_000)
    ).unwrap();
    const second = await (
      await subject.replayDeadLettersForEndpoint(tenantId, targetEndpointId, nowMs + 2_001)
    ).unwrap();
    const exhausted = await (
      await subject.replayDeadLettersForEndpoint(tenantId, targetEndpointId, nowMs + 2_002)
    ).unwrap();

    // Assert
    should(first).have.length(100);
    should(second).have.length(1);
    should(exhausted).have.length(0);
    should(new Set([...first, ...second].map(job => job.id)).size).equal(101);
    should(subject.deadLetterEndpointJobs.has(`${tenantId}\u0000${targetEndpointId}`)).be.false();
    should(subject.deadLetterEndpointJobs.get(`${tenantId}\u0000${noiseEndpointId}`)?.size).equal(1_001);
  }, 30_000);

  it('should skip a full stale endpoint-index page before replaying a retained obligation', async () => {
    // Arrange
    const nowMs = Date.UTC(2026, 0, 1);
    const clock = new ManualClock(nowMs);
    const subject = new MemoryLandscapeStore('raichu', clock);
    const endpointId = 'endpoint-stale-prefix';
    const input = atomicRequestForEndpoint('event-after-stale-prefix', endpointId, nowMs);
    await seedDeadLetters(subject, [input]);
    const indexKey = `${tenantId}\u0000${endpointId}`;
    const endpointIndex = subject.deadLetterEndpointJobs.get(indexKey);
    should(endpointIndex).not.be.undefined();
    for (let index = 0; index < 100; index += 1) {
      endpointIndex?.set(`stale-job-${String(index).padStart(3, '0')}`, nowMs - 1);
    }

    // Act
    const replayed = await (await subject.replayDeadLettersForEndpoint(tenantId, endpointId, nowMs + 1_000)).unwrap();

    // Assert
    should(replayed.map(job => job.id)).deepEqual([input.jobs[0]?.id]);
    should(subject.deadLetterEndpointJobs.has(indexKey)).be.false();
  });
});
