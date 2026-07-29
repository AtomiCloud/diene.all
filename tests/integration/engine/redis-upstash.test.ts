import { afterAll, beforeAll, beforeEach, describe, it } from 'bun:test';
import Redis from 'ioredis';
import should from 'should';
import { GenericContainer, type StartedTestContainer, Wait } from 'testcontainers';
import {
  type AtomicAcceptRequest,
  DEDUP_WINDOW_SECONDS,
  type DeliveryJob,
  type EventMonthArchiveManifest,
  type FlowStore,
  type LandscapeRuntimeConfig,
} from '../../../src/domain/index.ts';
import { ManualClock } from '../../../src/runtime/fakes.ts';
import { MemoryLandscapeStore } from '../../../src/storage/memory.ts';
import { RedisRuntimeConfigStore } from '../../../src/storage/redis-config.ts';
import { RedisFlowStore } from '../../../src/storage/redis-flow.ts';

const encoder = new TextEncoder();

const atomicRequestForEndpoints = (
  eventId: string,
  endpointIds: readonly string[],
  receivedAtMs = Date.UTC(2026, 0, 1),
): AtomicAcceptRequest => ({
  dedupKey: `dedup:external%2Facme:paid:${eventId}`,
  dedupTtlSeconds: DEDUP_WINDOW_SECONDS,
  envelope: {
    id: eventId,
    tenantId: 'external/acme',
    routeId: 'paid',
    provider: 'stripe',
    landingLandscape: 'raichu',
    receivedAtMs,
    providerEventId: eventId,
    dedupId: eventId,
    rawBody: encoder.encode(`{"id":"${eventId}"}`),
    headers: { 'content-type': 'application/json' },
    verificationMetadata: {},
    obligations: endpointIds.map(endpointId => ({
      id: `${eventId}:${endpointId}`,
      endpointId,
      address: 'https://receiver.example/webhook',
      addressKind: 'canonical',
      signingSecretRef: 'delivery/acme',
    })),
  },
  jobs: endpointIds.map(endpointId => ({
    id: `${eventId}:${endpointId}`,
    eventId,
    tenantId: 'external/acme',
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
  })),
});

const atomicRequestForEndpoint = (
  eventId: string,
  endpointId: string,
  receivedAtMs = Date.UTC(2026, 0, 1),
): AtomicAcceptRequest => atomicRequestForEndpoints(eventId, [endpointId], receivedAtMs);

const atomicRequest = (eventId = 'event-redis', receivedAtMs = Date.UTC(2026, 0, 1)): AtomicAcceptRequest =>
  atomicRequestForEndpoint(eventId, 'endpoint-a', receivedAtMs);

const forEachBatch = async <Value>(
  values: readonly Value[],
  batchSize: number,
  operation: (value: Value) => Promise<void>,
): Promise<void> => {
  for (let offset = 0; offset < values.length; offset += batchSize) {
    await Promise.all(values.slice(offset, offset + batchSize).map(operation));
  }
};

const archiveManifest = (month: string, version: number): EventMonthArchiveManifest => ({
  objectPath: `${month}/versions/${String(version)}/manifest`,
  byteLength: 1,
  sha256: 'manifest-sha256',
  partCount: 1,
  partsSha256: 'parts-sha256',
  eventCount: 1,
  jobCount: 1,
  deadLetterCount: 0,
  archiveByteLength: 1,
});

interface EvalGate {
  readonly redis: Redis;
  readonly entered: Promise<void>;
  release(): void;
}

const gateEvalContaining = (delegate: Redis, marker: string): EvalGate => {
  let announceEntry: (() => void) | undefined;
  let releaseEval: (() => void) | undefined;
  const entered = new Promise<void>(resolve => {
    announceEntry = resolve;
  });
  const released = new Promise<void>(resolve => {
    releaseEval = resolve;
  });
  const evaluate = delegate.eval.bind(delegate) as unknown as (...argumentsList: unknown[]) => Promise<unknown>;
  let armed = true;
  const gated = new Proxy(delegate, {
    get(target, property) {
      if (property === 'eval') {
        return async (...argumentsList: unknown[]): Promise<unknown> => {
          if (armed && typeof argumentsList[0] === 'string' && argumentsList[0].includes(marker)) {
            armed = false;
            announceEntry?.();
            await released;
          }
          return evaluate(...argumentsList);
        };
      }
      const value = Reflect.get(target, property, target) as unknown;
      return typeof value === 'function' ? value.bind(target) : value;
    },
  }) as Redis;
  return {
    redis: gated,
    entered,
    release: () => releaseEval?.(),
  };
};

const rewriteEvalCommand = (delegate: Redis, command: string, replacement: string): Redis => {
  const evaluate = delegate.eval.bind(delegate) as unknown as (...argumentsList: unknown[]) => Promise<unknown>;
  return new Proxy(delegate, {
    get(target, property) {
      if (property === 'eval') {
        return async (...argumentsList: unknown[]): Promise<unknown> => {
          const script = argumentsList[0];
          const rewritten = typeof script === 'string' ? script.replaceAll(`'${command}'`, `'${replacement}'`) : script;
          return evaluate(rewritten, ...argumentsList.slice(1));
        };
      }
      const value = Reflect.get(target, property, target) as unknown;
      return typeof value === 'function' ? value.bind(target) : value;
    },
  }) as Redis;
};

interface CountedRedis {
  readonly redis: Redis;
  calls(): number;
}

const countHashScans = (delegate: Redis, hashKey: string): CountedRedis => {
  const scan = delegate.hscan.bind(delegate) as unknown as (...argumentsList: unknown[]) => Promise<unknown>;
  let calls = 0;
  return {
    redis: new Proxy(delegate, {
      get(target, property) {
        if (property === 'hscan') {
          return async (...argumentsList: unknown[]): Promise<unknown> => {
            if (argumentsList[0] === hashKey) {
              calls += 1;
            }
            return scan(...argumentsList);
          };
        }
        const value = Reflect.get(target, property, target) as unknown;
        return typeof value === 'function' ? value.bind(target) : value;
      },
    }) as Redis,
    calls: () => calls,
  };
};

const collectDeadLetterPages = async (
  store: Pick<FlowStore, 'listDeadLetterPage'>,
  tenantId: string,
  limit: number,
): Promise<Readonly<{ jobIds: readonly string[]; cursorLengths: readonly number[]; pageSizes: readonly number[] }>> => {
  const jobIds: string[] = [];
  const cursorLengths: number[] = [];
  const pageSizes: number[] = [];
  let cursor: string | undefined;
  let calls = 0;
  do {
    const page = await (await store.listDeadLetterPage(tenantId, cursor, limit)).unwrap();
    jobIds.push(...page.items.map(entry => entry.jobId));
    pageSizes.push(page.items.length);
    cursor = page.nextCursor;
    if (cursor !== undefined) {
      cursorLengths.push(cursor.length);
    }
    calls += 1;
    if (calls > 100) {
      throw new Error('dead-letter pagination did not terminate within its bounded test budget');
    }
  } while (cursor !== undefined);
  return { jobIds, cursorLengths, pageSizes };
};

describe('Redis/Upstash landscape store', () => {
  let container: StartedTestContainer;
  let redis: Redis;

  beforeAll(async () => {
    container = await new GenericContainer('redis:7.4.2-alpine')
      .withExposedPorts(6379)
      .withWaitStrategy(Wait.forLogMessage(/Ready to accept connections/))
      .start();
    redis = new Redis({
      host: container.getHost(),
      port: container.getMappedPort(6379),
      maxRetriesPerRequest: 1,
    });
  });

  beforeEach(async () => {
    await redis.flushdb();
  });

  afterAll(async () => {
    redis?.disconnect();
    await container?.stop();
  });

  it('should atomically SET NX for 72 hours and create one event plus one obligation under concurrency', async () => {
    // Arrange
    const subject = new RedisFlowStore('raichu', redis);
    const input = atomicRequest();

    // Act
    const results = await Promise.all(Array.from({ length: 12 }, () => subject.acceptOnce(input)));
    const outcomes = await Promise.all(results.map(result => result.unwrap()));
    const ttl = await redis.ttl(input.dedupKey);
    const eventCount = await redis.xlen('evt:external%2Facme:2026-01');
    const legacyQueueExists = await redis.exists('q:deliver');
    const readyBeforeAcknowledgement = await redis.zcard('q:deliver:ready');
    await (await subject.acknowledgeEvent(input.envelope.id, input.envelope.receivedAtMs)).unwrap();
    const readyAfterAcknowledgement = await redis.zcard('q:deliver:ready');
    const retained = await (
      await subject.listRetainedEvents({
        tenantId: 'external/acme',
        provider: 'stripe',
        endpointId: 'endpoint-a',
        status: 'pending',
      })
    ).unwrap();

    // Assert
    should(outcomes.filter(outcome => outcome.kind === 'accepted')).have.length(1);
    should(outcomes.filter(outcome => outcome.kind === 'duplicate')).have.length(11);
    should(ttl).be.within(DEDUP_WINDOW_SECONDS - 1, DEDUP_WINDOW_SECONDS);
    should(eventCount).equal(1);
    should(legacyQueueExists).equal(0);
    should(readyBeforeAcknowledgement).equal(0);
    should(readyAfterAcknowledgement).equal(1);
    should(new Set(outcomes.map(outcome => outcome.eventId)).size).equal(1);
    should(await redis.exists('event:event-redis')).equal(1);
    should(await redis.exists('job:event-redis%3Aendpoint-a')).equal(1);
    should(await redis.zcard('evt-index:external%2Facme')).equal(1);
    should(retained.items.map(item => item.envelope.id)).deepEqual(['event-redis']);
  });

  it('should leave no dedup claim or partial record when acceptance preflight fails', async () => {
    // Arrange
    const subject = new RedisFlowStore('raichu', redis);
    const input = atomicRequest('event-failure-atomic');
    const activeMonthJobsKey = 'active:external%2Facme:2026-01';
    await redis.set(activeMonthJobsKey, 'wrong-type');

    // Act
    const failed = await subject.acceptOnce(input);
    const dedupAfterFailure = await redis.exists(input.dedupKey);
    const eventAfterFailure = await redis.exists('event:event-failure-atomic');
    const jobAfterFailure = await redis.exists('job:event-failure-atomic%3Aendpoint-a');
    await redis.del(activeMonthJobsKey);
    const retried = await (await subject.acceptOnce(input)).unwrap();

    // Assert
    should(await failed.isErr()).be.true();
    should(dedupAfterFailure).equal(0);
    should(eventAfterFailure).equal(0);
    should(jobAfterFailure).equal(0);
    should(retried.kind).equal('accepted');
    should(await redis.exists('q:deliver')).equal(0);
  });

  it('should gate due work on acknowledgement and lease it to only one replica with expiry recovery', async () => {
    // Arrange
    const firstReplica = new RedisFlowStore('raichu', redis);
    const secondReplica = new RedisFlowStore('raichu', redis);
    const nowMs = Date.now();
    const input = atomicRequest('event-leased', nowMs);
    await (await firstReplica.acceptOnce(input)).unwrap();

    // Act
    const beforeAcknowledgement = await Promise.all([
      firstReplica.claimDueJobs({
        claimToken: 'replica-a-before',
        leaseMs: 50,
        limit: 1,
        nowMs,
      }),
      secondReplica.claimDueJobs({
        claimToken: 'replica-b-before',
        leaseMs: 50,
        limit: 1,
        nowMs,
      }),
    ]);
    await (await firstReplica.acknowledgeEvent(input.envelope.id, nowMs)).unwrap();
    const contenders = await Promise.all([
      firstReplica.claimDueJobs({
        claimToken: 'replica-a',
        leaseMs: 50,
        limit: 1,
        nowMs,
      }),
      secondReplica.claimDueJobs({
        claimToken: 'replica-b',
        leaseMs: 50,
        limit: 1,
        nowMs,
      }),
    ]);
    const claimed = (await Promise.all(contenders.map(result => result.unwrap()))).flat();
    const blocked = await (
      await secondReplica.claimDueJobs({
        claimToken: 'replica-blocked',
        leaseMs: 50,
        limit: 1,
        nowMs,
      })
    ).unwrap();
    const recovered = await (
      await secondReplica.claimDueJobs({
        claimToken: 'replica-recovery',
        leaseMs: 1_000,
        limit: 1,
        nowMs: nowMs + 51,
      })
    ).unwrap();
    const staleCompletion = await firstReplica.completeJob(input.jobs[0]?.id ?? '', claimed[0]?.claimToken);
    const recoveredCompletion = await secondReplica.completeJob(input.jobs[0]?.id ?? '', recovered[0]?.claimToken);

    // Assert
    for (const result of beforeAcknowledgement) {
      should(await (await result.unwrap()).length).equal(0);
    }
    should(claimed).have.length(1);
    should(blocked).have.length(0);
    should(recovered).have.length(1);
    should(await staleCompletion.isErr()).be.true();
    should((await recoveredCompletion.unwrap()).status).equal('completed');
  });

  it('should paginate the tenant-local retained-event index without skipping an over-fetched batch', async () => {
    // Arrange
    const subject = new RedisFlowStore('raichu', redis);
    const receivedAtMs = Date.UTC(2026, 0, 1);
    for (let index = 1; index <= 3; index += 1) {
      await (await subject.acceptOnce(atomicRequest(`event-page-${index}`, receivedAtMs + index))).unwrap();
    }

    // Act
    const first = await (await subject.listRetainedEvents({ tenantId: 'external/acme', limit: 1 })).unwrap();
    const second = await (
      await subject.listRetainedEvents({
        tenantId: 'external/acme',
        limit: 1,
        cursor: first.nextCursor,
      })
    ).unwrap();

    // Assert
    should(first.items.map(item => item.envelope.id)).deepEqual(['event-page-3']);
    should(second.items.map(item => item.envelope.id)).deepEqual(['event-page-2']);
  });

  it('should fence archive deletion against replay and advance the month version after an expired export', async () => {
    // Arrange
    const subject = new RedisFlowStore('raichu', redis);
    const input = atomicRequest('event-archive-fence', Date.UTC(2026, 0, 15));
    await (await subject.acceptOnce(input)).unwrap();
    await (await subject.acknowledgeEvent(input.envelope.id, input.envelope.receivedAtMs)).unwrap();
    await (await subject.completeJob(input.jobs[0]?.id ?? '')).unwrap();
    const lease = await (
      await subject.beginEventMonthArchive({
        tenantId: input.envelope.tenantId,
        month: '2026-01',
        leaseToken: 'export-owner',
        nowMs: 10_000,
        leaseMs: 100,
      })
    ).unwrap();

    // Act
    const blockedDuringExport = await subject.replayEndpoint(input.envelope.id, 'endpoint-a', 10_050);
    const replayedAfterExpiry = await subject.replayEndpoint(input.envelope.id, 'endpoint-a', 10_101);
    const staleSeal = await subject.sealEventMonthArchive(lease, archiveManifest('2026-01', lease.version));
    await (await subject.completeJob(input.jobs[0]?.id ?? '')).unwrap();
    const deletionLease = await (
      await subject.beginEventMonthArchive({
        tenantId: input.envelope.tenantId,
        month: '2026-01',
        leaseToken: 'delete-owner',
        nowMs: 10_102,
        leaseMs: 100,
      })
    ).unwrap();
    const sealed = await (
      await subject.sealEventMonthArchive(deletionLease, archiveManifest('2026-01', deletionLease.version))
    ).unwrap();
    const blockedDuringDeletion = await subject.replayEndpoint(input.envelope.id, 'endpoint-a', 20_000);
    const persisted = await (await subject.getJob(input.jobs[0]?.id ?? '')).unwrap();

    // Assert
    should(await blockedDuringExport.isErr()).be.true();
    should((await blockedDuringExport.unwrapErr()).code).equal('conflict');
    should(await replayedAfterExpiry.isOk()).be.true();
    should((await replayedAfterExpiry.unwrap()).createdAtMs).equal(10_101);
    should(await staleSeal.isErr()).be.true();
    should((await staleSeal.unwrapErr()).code).equal('conflict');
    should(deletionLease.version).equal(lease.version + 1);
    should(sealed.phase).equal('deleting');
    should(await blockedDuringDeletion.isErr()).be.true();
    should((await blockedDuringDeletion.unwrapErr()).code).equal('conflict');
    should(persisted?.status).equal('completed');
    should(await redis.exists(`event:${encodeURIComponent(input.envelope.id)}`)).equal(1);
  });

  it('should reject stale replay and resume compare-and-swap writes without overwriting concurrent job state', async () => {
    // Arrange: gate the replay Lua invocation after its optimistic read.
    const base = new RedisFlowStore('raichu', redis);
    const replayInput = atomicRequest('event-stale-replay', Date.UTC(2026, 0, 16));
    await (await base.acceptOnce(replayInput)).unwrap();
    await (await base.completeJob(replayInput.jobs[0]?.id ?? '')).unwrap();
    const replayGate = gateEvalContaining(redis, 'replay index has an incompatible Redis type');
    const replayStore = new RedisFlowStore('raichu', replayGate.redis);
    const replayPromise = replayStore.replayEndpoint(replayInput.envelope.id, 'endpoint-a', 20_000);
    await replayGate.entered;
    const replayJobKey = `job:${encodeURIComponent(replayInput.jobs[0]?.id ?? '')}`;
    const replayCurrent = JSON.parse((await redis.get(replayJobKey)) ?? '{}') as DeliveryJob;
    await redis.set(replayJobKey, JSON.stringify({ ...replayCurrent, replayCount: 41 }));

    // Act: let the stale script run, then repeat the same interleaving for endpoint resume.
    replayGate.release();
    const replayResult = await replayPromise;
    const resumeInput = atomicRequest('event-stale-resume', Date.UTC(2026, 0, 17));
    await (await base.acceptOnce(resumeInput)).unwrap();
    await (await base.pauseJob(resumeInput.jobs[0]?.id ?? '')).unwrap();
    const resumeGate = gateEvalContaining(redis, 'replay index has an incompatible Redis type');
    const resumeStore = new RedisFlowStore('raichu', resumeGate.redis);
    const resumePromise = resumeStore.resumeEndpoint('external/acme', 'endpoint-a', 30_000);
    await resumeGate.entered;
    const resumeJobKey = `job:${encodeURIComponent(resumeInput.jobs[0]?.id ?? '')}`;
    const resumeCurrent = JSON.parse((await redis.get(resumeJobKey)) ?? '{}') as DeliveryJob;
    await redis.set(resumeJobKey, JSON.stringify({ ...resumeCurrent, replayCount: 73 }));
    resumeGate.release();
    const resumeResult = await resumePromise;
    const replayPersisted = JSON.parse((await redis.get(replayJobKey)) ?? '{}') as DeliveryJob;
    const resumePersisted = JSON.parse((await redis.get(resumeJobKey)) ?? '{}') as DeliveryJob;

    // Assert
    should(await replayResult.isErr()).be.true();
    should((await replayResult.unwrapErr()).code).equal('conflict');
    should(replayPersisted.replayCount).equal(41);
    should(await resumeResult.isErr()).be.true();
    should((await resumeResult.unwrapErr()).code).equal('conflict');
    should(resumePersisted.replayCount).equal(73);
    should(await redis.zscore('q:deliver:ready', resumeInput.jobs[0]?.id ?? '')).be.null();
  });

  it('should expire each paused obligation exactly once across concurrent replicas', async () => {
    // Arrange
    const firstReplica = new RedisFlowStore('raichu', redis);
    const secondReplica = new RedisFlowStore('raichu', redis);
    const nowMs = Date.now();
    const retryWindowMs = 72 * 60 * 60 * 1_000;
    const input = atomicRequest('event-paused-expiry', nowMs - retryWindowMs);
    await (await firstReplica.acceptOnce(input)).unwrap();
    await (await firstReplica.pauseJob(input.jobs[0]?.id ?? '')).unwrap();

    // Act
    const contenders = await Promise.all([
      firstReplica.expirePausedJobs(nowMs, 10),
      secondReplica.expirePausedJobs(nowMs, 10),
    ]);
    const expired = (await Promise.all(contenders.map(result => result.unwrap()))).flat();
    const persisted = await (await firstReplica.getJob(input.jobs[0]?.id ?? '')).unwrap();
    const month = new Date(input.envelope.receivedAtMs).toISOString().slice(0, 7);

    // Assert
    should(expired).have.length(1);
    should(expired[0]?.reason).equal('retry-window-expired');
    should(persisted?.status).equal('dead-letter');
    should(await redis.zscore('q:paused:expiries', input.jobs[0]?.id ?? '')).be.null();
    should(await redis.hlen(`dlq:external%2Facme:${month}`)).equal(1);
    should(await redis.hlen(`event-dlq:${encodeURIComponent(input.envelope.id)}`)).equal(1);
    should(await redis.scard(`active:external%2Facme:${month}`)).equal(0);
  });

  it('should drain endpoint dead letters across bounded replays without tenant-stream starvation', async () => {
    // Arrange: target entries precede more than one thousand unrelated entries for the same tenant.
    const subject = new RedisFlowStore('raichu', redis);
    const nowMs = Date.now();
    const targetEndpointId = 'endpoint-target';
    const noiseEndpointId = 'endpoint-noise';
    const targetInputs = Array.from({ length: 101 }, (_, index) =>
      atomicRequestForEndpoint(`event-target-${String(index).padStart(4, '0')}`, targetEndpointId, nowMs + index),
    );
    const noiseInputs = Array.from({ length: 1_001 }, (_, index) =>
      atomicRequestForEndpoint(`event-noise-${String(index).padStart(4, '0')}`, noiseEndpointId, nowMs + index),
    );
    const seedDeadLetter = async (input: AtomicAcceptRequest): Promise<void> => {
      await (await subject.acceptOnce(input)).unwrap();
      await (
        await subject.deadLetter(input.jobs[0]?.id ?? '', input.envelope.receivedAtMs, `exhausted-${input.envelope.id}`)
      ).unwrap();
    };
    await forEachBatch(targetInputs, 25, seedDeadLetter);
    await forEachBatch(noiseInputs, 25, seedDeadLetter);
    const targetIndexKey = 'dlq-endpoint:external%2Facme:endpoint-target';
    const staleTargetIds = Array.from(
      { length: 100 },
      (_, index) => `missing-target-job-${String(index).padStart(3, '0')}`,
    );
    await redis.hset(targetIndexKey, ...staleTargetIds.flatMap(id => [id, 'missing-job']));

    // Act
    const first = await (
      await subject.replayDeadLettersForEndpoint('external/acme', targetEndpointId, nowMs + 2_000)
    ).unwrap();
    const second = await (
      await subject.replayDeadLettersForEndpoint('external/acme', targetEndpointId, nowMs + 2_001)
    ).unwrap();
    const exhausted = await (
      await subject.replayDeadLettersForEndpoint('external/acme', targetEndpointId, nowMs + 2_002)
    ).unwrap();

    // Assert
    should(first).have.length(100);
    should(second).have.length(1);
    should(exhausted).have.length(0);
    should(new Set([...first, ...second].map(job => job.id))).have.size(101);
    should(await redis.hlen(targetIndexKey)).equal(0);
    should(await redis.hlen('dlq-endpoint:external%2Facme:endpoint-noise')).equal(1_001);
  });

  it('should physically expire idle DLQ hashes and indexes on Redis server time', async () => {
    // Arrange
    const dlqRetentionMs = 500;
    const subject = new RedisFlowStore('raichu', redis, { dlqRetentionMs });
    const nowMs = Date.now();
    const endpointId = 'endpoint-idle-expiry';
    const input = atomicRequestForEndpoint('event-idle-expiry', endpointId, nowMs);
    const month = new Date(input.envelope.receivedAtMs).toISOString().slice(0, 7);
    const keys = [
      `dlq:external%2Facme:${month}`,
      `event-dlq:${encodeURIComponent(input.envelope.id)}`,
      `dlq-endpoint:external%2Facme:${endpointId}`,
      'dlq-months:external%2Facme',
    ];
    await (await subject.acceptOnce(input)).unwrap();
    const deadLettered = await subject.deadLetter(input.jobs[0]?.id ?? '', nowMs, 'idle-retention');
    if (await deadLettered.isErr()) {
      throw new Error(JSON.stringify(await deadLettered.unwrapErr()));
    }
    await deadLettered.unwrap();
    should(await redis.exists(...keys)).equal(keys.length);

    // Act: no storage read or append occurs while Redis ages the final idle batch out.
    await Bun.sleep(dlqRetentionMs * 3);
    const retainedTypes = await Promise.all(keys.map(key => redis.type(key)));

    // Assert
    should(retainedTypes).deepEqual(keys.map(() => 'none'));
    should(await redis.exists('dlq-month-expiries:external%2Facme')).equal(0);
  });

  it('should fail closed before mutating DLQ state when hash-field expiry semantics are unavailable', async () => {
    // Arrange: rewrite only the capability command to reproduce an older/unsupported Redis service.
    const dlqRetentionMs = 10_000;
    const subject = new RedisFlowStore('raichu', rewriteEvalCommand(redis, 'HPEXPIREAT', 'UNSUPPORTED_HPEXPIREAT'), {
      dlqRetentionMs,
    });
    const nowMs = Date.now();
    const input = atomicRequestForEndpoint('event-unsupported-field-expiry', 'endpoint-unsupported', nowMs);
    const jobId = input.jobs[0]?.id ?? '';
    const month = new Date(nowMs).toISOString().slice(0, 7);
    await (await subject.acceptOnce(input)).unwrap();

    // Act
    const result = await subject.deadLetter(jobId, nowMs, 'unsupported-field-expiry');

    // Assert: only the short-lived capability probe may have been written before the command error.
    should(await result.isErr()).be.true();
    const failure = await result.unwrapErr();
    should(failure.operation).equal('dead-letter');
    should(failure.message).match(/UNSUPPORTED_HPEXPIREAT|unknown (?:Redis )?command/i);
    should((await (await subject.getJob(jobId)).unwrap())?.status).equal('pending');
    should(await redis.sismember(`active:external%2Facme:${month}`, jobId)).equal(1);
    should(
      await redis.exists(
        `dlq:external%2Facme:${month}`,
        `event-dlq:${encodeURIComponent(input.envelope.id)}`,
        'dlq-endpoint:external%2Facme:endpoint-unsupported',
        'dlq-months:external%2Facme',
      ),
    ).equal(0);
    should(await redis.type('dlq:field-expiry-probe')).equal('hash');
    should(await redis.pttl('dlq:field-expiry-probe')).be.within(1, dlqRetentionMs);
  });

  it('should preserve each staggered DLQ field only until its own server-timed deadline', async () => {
    // Arrange: A shares its event with B and its endpoint with C, so every aggregate key remains live after A expires.
    const dlqRetentionMs = 1_200;
    const subject = new RedisFlowStore('raichu', redis, { dlqRetentionMs });
    const nowMs = Date.now();
    const sharedEvent = atomicRequestForEndpoints(
      'event-staggered-shared',
      ['endpoint-staggered-shared', 'endpoint-staggered-event-later'],
      nowMs,
    );
    const laterEndpointEvent = atomicRequestForEndpoint(
      'event-staggered-endpoint-later',
      'endpoint-staggered-shared',
      nowMs + 1,
    );
    await (await subject.acceptOnce(sharedEvent)).unwrap();
    await (await subject.acceptOnce(laterEndpointEvent)).unwrap();
    const firstJob = sharedEvent.jobs[0];
    const eventLaterJob = sharedEvent.jobs[1];
    const endpointLaterJob = laterEndpointEvent.jobs[0];
    should(firstJob).not.be.undefined();
    should(eventLaterJob).not.be.undefined();
    should(endpointLaterJob).not.be.undefined();
    const firstField = `${encodeURIComponent(firstJob?.id ?? '')}:${String(firstJob?.replayCount ?? 0)}`;
    const eventLaterField = `${encodeURIComponent(eventLaterJob?.id ?? '')}:${String(eventLaterJob?.replayCount ?? 0)}`;
    const endpointLaterField = `${encodeURIComponent(endpointLaterJob?.id ?? '')}:${String(endpointLaterJob?.replayCount ?? 0)}`;
    const month = new Date(nowMs).toISOString().slice(0, 7);
    const monthDlq = `dlq:external%2Facme:${month}`;
    const sharedEventDlq = `event-dlq:${encodeURIComponent(sharedEvent.envelope.id)}`;
    const laterEventDlq = `event-dlq:${encodeURIComponent(laterEndpointEvent.envelope.id)}`;
    const sharedEndpointDlq = 'dlq-endpoint:external%2Facme:endpoint-staggered-shared';
    const eventLaterEndpointDlq = 'dlq-endpoint:external%2Facme:endpoint-staggered-event-later';
    const monthIndex = 'dlq-months:external%2Facme';
    await (await subject.deadLetter(firstJob?.id ?? '', nowMs, 'first-staggered')).unwrap();
    const firstTtl = (await redis.call('HPTTL', monthDlq, 'FIELDS', 1, firstField)) as unknown;
    should(Array.isArray(firstTtl)).be.true();
    should(Number(Array.isArray(firstTtl) ? firstTtl[0] : -1)).be.within(1, dlqRetentionMs);

    await Bun.sleep(700);
    await (await subject.deadLetter(eventLaterJob?.id ?? '', nowMs + 700, 'event-later')).unwrap();
    await (await subject.deadLetter(endpointLaterJob?.id ?? '', nowMs + 701, 'endpoint-later')).unwrap();

    // Act: no storage cleanup read or append occurs before A's deadline assertion.
    await Bun.sleep(700);
    const atFirstDeadline = {
      month: await redis.hmget(monthDlq, firstField, eventLaterField, endpointLaterField),
      event: await redis.hmget(sharedEventDlq, firstField, eventLaterField),
      endpoint: await redis.hmget(sharedEndpointDlq, firstJob?.id ?? '', endpointLaterJob?.id ?? ''),
      monthIndex: await redis.hexists(monthIndex, month),
      laterTtl: (await redis.call('HPTTL', monthDlq, 'FIELDS', 1, eventLaterField)) as unknown,
    };

    // Assert: A is physically absent while B/C remain, then every aggregate key disappears at the final deadline.
    should(atFirstDeadline.month[0]).be.null();
    should(atFirstDeadline.month[1]).not.be.null();
    should(atFirstDeadline.month[2]).not.be.null();
    should(atFirstDeadline.event[0]).be.null();
    should(atFirstDeadline.event[1]).not.be.null();
    should(atFirstDeadline.endpoint[0]).be.null();
    should(atFirstDeadline.endpoint[1]).not.be.null();
    should(atFirstDeadline.monthIndex).equal(1);
    should(Number(Array.isArray(atFirstDeadline.laterTtl) ? atFirstDeadline.laterTtl[0] : -1)).be.within(
      1,
      dlqRetentionMs,
    );
    should(await redis.exists('dlq:field-expiry-probe')).equal(0);
    await Bun.sleep(700);
    const finalKeys = [monthDlq, sharedEventDlq, laterEventDlq, sharedEndpointDlq, eventLaterEndpointDlq, monthIndex];
    should(await Promise.all(finalKeys.map(key => redis.type(key)))).deepEqual(finalKeys.map(() => 'none'));
    should(await redis.exists('dlq-month-expiries:external%2Facme')).equal(0);
  });

  it('should traverse opaque DLQ pages without loss across multiple hash scans', async () => {
    // Arrange: more than Redis' default compact-hash threshold forces multiple HSCAN batches.
    const nowMs = Date.now();
    const month = new Date(nowMs).toISOString().slice(0, 7);
    const hashKey = `dlq:external%2Facme:${month}`;
    const counted = countHashScans(redis, hashKey);
    const subject = new RedisFlowStore('raichu', counted.redis);
    const memory = new MemoryLandscapeStore('raichu', new ManualClock(nowMs));
    const inputs = Array.from({ length: 600 }, (_, index) =>
      atomicRequest(`event-page-parity-${String(index).padStart(4, '0')}`, nowMs + index),
    );
    await forEachBatch(inputs, 25, async input => {
      await (await subject.acceptOnce(input)).unwrap();
      await (await memory.acceptOnce(input)).unwrap();
      const jobId = input.jobs[0]?.id ?? '';
      await (await subject.deadLetter(jobId, input.envelope.receivedAtMs, `redis-${jobId}`)).unwrap();
      await (await memory.deadLetter(jobId, input.envelope.receivedAtMs, `memory-${jobId}`)).unwrap();
    });

    // Act: ordering is opaque and HSCAN is at-least-once; membership and cursor bounds are the shared contract.
    const pageLimit = 37;
    const redisPages = await collectDeadLetterPages(subject, 'external/acme', pageLimit);
    const memoryPages = await collectDeadLetterPages(memory, 'external/acme', pageLimit);

    // Assert
    should(counted.calls()).be.above(1);
    should(redisPages.pageSizes.every(size => size >= 1 && size <= pageLimit)).be.true();
    should(redisPages.cursorLengths.every(length => length <= 256 * 1_024)).be.true();
    const redisMembership = [...new Set(redisPages.jobIds)].sort();
    const memoryMembership = [...new Set(memoryPages.jobIds)].sort();
    const expectedMembership = inputs.map(input => input.jobs[0]?.id ?? '').sort();
    should(redisMembership).deepEqual(memoryMembership);
    should(redisMembership).deepEqual(expectedMembership);
  });

  it('should page and age DLQ entries, then remove their month only through fenced bounded archive deletion', async () => {
    // Arrange
    const subject = new RedisFlowStore('raichu', redis);
    const nowMs = Date.now();
    const month = new Date(nowMs).toISOString().slice(0, 7);
    const dlq = `dlq:external%2Facme:${month}`;
    const dlqMonths = 'dlq-months:external%2Facme';
    const inputs = Array.from({ length: 3 }, (_, index) => atomicRequest(`event-dlq-${index + 1}`, nowMs + index));
    for (const [index, input] of inputs.entries()) {
      await (await subject.acceptOnce(input)).unwrap();
      await (await subject.deadLetter(input.jobs[0]?.id ?? '', nowMs + index, `failure-${index + 1}`)).unwrap();
    }

    // Act: page retained entries, export bounded pages, seal, and delete one obligation at a time.
    const first = await (await subject.listDeadLetterPage('external/acme', undefined, 2)).unwrap();
    const second = await (await subject.listDeadLetterPage('external/acme', first.nextCursor, 2)).unwrap();
    const retainedDlqLength = await redis.hlen(dlq);
    const dlqIndexType = await redis.type(dlqMonths);
    const lease = await (
      await subject.beginEventMonthArchive({
        tenantId: 'external/acme',
        month,
        leaseToken: 'bounded-delete',
        nowMs,
        leaseMs: 60_000,
      })
    ).unwrap();
    let archiveCursor: string | undefined;
    let archivedEvents = 0;
    let archivedDeadLetters = 0;
    const archivePageSizes: number[] = [];
    do {
      const pageResult = await subject.readEventMonthArchivePage(lease, archiveCursor, 2, 64 * 1_024);
      if (await pageResult.isErr()) {
        throw new Error(JSON.stringify(await pageResult.unwrapErr()));
      }
      const page = await pageResult.unwrap();
      archivedEvents += page.eventCount;
      archivedDeadLetters += page.deadLetterCount;
      archivePageSizes.push(page.body.byteLength);
      archiveCursor = page.nextCursor;
    } while (archiveCursor !== undefined);
    const sealed = await (
      await subject.sealEventMonthArchive(lease, {
        ...archiveManifest(month, lease.version),
        eventCount: archivedEvents,
        jobCount: 3,
        deadLetterCount: archivedDeadLetters,
      })
    ).unwrap();
    let deletionCalls = 0;
    let deletionDone = false;
    while (!deletionDone && deletionCalls < 10) {
      const page = await (await subject.deleteEventMonthArchivePage(sealed, 1)).unwrap();
      should(page.deletedJobs).be.belowOrEqual(1);
      should(page.deletedEvents).be.belowOrEqual(1);
      deletionDone = page.done;
      deletionCalls += 1;
    }
    await (await subject.completeEventMonthArchive(sealed)).unwrap();

    // Assert
    should(retainedDlqLength).equal(3);
    should(dlqIndexType).equal('hash');
    should(await redis.type(dlqMonths)).equal('none');
    should(await redis.exists(dlq)).equal(0);
    should(first.items).have.length(2);
    should(second.items).have.length(1);
    should([...first.items, ...second.items].map(entry => entry.jobId).sort()).deepEqual(
      inputs.map(input => input.jobs[0]?.id ?? '').sort(),
    );
    should(archivedEvents).equal(3);
    should(archivedDeadLetters).equal(3);
    should(archivePageSizes).have.length(2);
    should(archivePageSizes.every(size => size <= 64 * 1_024)).be.true();
    should(deletionDone).be.true();
    should(deletionCalls).equal(3);
    for (const input of inputs) {
      should(await redis.exists(`event-dlq:${encodeURIComponent(input.envelope.id)}`)).equal(0);
    }
  });

  it('should keep readers on the active generation until a compare-and-swap pointer flip', async () => {
    // Arrange
    const subject = new RedisRuntimeConfigStore(redis);
    const first: LandscapeRuntimeConfig = {
      generation: 1,
      landscape: 'raichu',
      compiledAtMs: 1,
      sourceRevision: 'one',
      tenants: [],
    };
    const second: LandscapeRuntimeConfig = {
      ...first,
      generation: 2,
      compiledAtMs: 2,
      sourceRevision: 'two',
    };
    await (await subject.stage(first)).unwrap();
    await (await subject.activate(1, null)).unwrap();

    // Act
    await (await subject.stage(second)).unwrap();
    const before = await (await subject.readActive()).unwrap();
    await (await subject.activate(2, 1)).unwrap();
    const after = await (await subject.readActive()).unwrap();

    // Assert
    should(before?.sourceRevision).equal('one');
    should(after?.sourceRevision).equal('two');
  });

  it('should reserve concurrently and retain expired generations without ever deleting the active pointer', async () => {
    // Arrange
    const subject = new RedisRuntimeConfigStore(redis);
    const reserved = await Promise.all(Array.from({ length: 16 }, () => subject.reserveGeneration()));
    const generations = await Promise.all(reserved.map(result => result.unwrap()));
    const [firstGeneration, secondGeneration, thirdGeneration, fourthGeneration] = generations;
    should(firstGeneration).be.a.Number();
    should(secondGeneration).be.a.Number();
    should(thirdGeneration).be.a.Number();
    should(fourthGeneration).be.a.Number();
    const config = (generation: number, sourceRevision: string): LandscapeRuntimeConfig => ({
      generation,
      landscape: 'raichu',
      compiledAtMs: generation,
      sourceRevision,
      tenants: [],
    });
    await (await subject.stage(config(firstGeneration ?? 0, 'first'))).unwrap();
    await (await subject.activate(firstGeneration ?? 0, null)).unwrap();
    await (await subject.stage(config(secondGeneration ?? 0, 'second'))).unwrap();
    await (await subject.activate(secondGeneration ?? 0, firstGeneration ?? 0)).unwrap();
    await (await subject.retainGeneration(firstGeneration ?? 0, 1_000)).unwrap();
    await (await subject.stage(config(thirdGeneration ?? 0, 'third'))).unwrap();
    await (await subject.stage(config(fourthGeneration ?? 0, 'fourth'))).unwrap();

    // Act
    const activeDiscard = await subject.discard(secondGeneration ?? 0);
    const activeRetention = await subject.retainGeneration(secondGeneration ?? 0, 1_000);
    const swaps = await Promise.all([
      subject.activate(thirdGeneration ?? 0, secondGeneration ?? 0, 2_000),
      subject.activate(fourthGeneration ?? 0, secondGeneration ?? 0, 2_000),
    ]);
    const active = await (await subject.readActive()).unwrap();
    const losingGeneration = active?.generation === thirdGeneration ? fourthGeneration : thirdGeneration;
    await (await subject.discard(losingGeneration ?? 0)).unwrap();
    await redis.zadd('cfg:retained', 0, String(active?.generation));
    const firstCleanup = await (await subject.discardExpired(1_000)).unwrap();
    const secondCleanup = await (await subject.discardExpired(2_000)).unwrap();

    // Assert
    should([...generations].sort((left, right) => left - right)).deepEqual(
      Array.from({ length: 16 }, (_, index) => index + 1),
    );
    should(await activeDiscard.isErr()).be.true();
    should((await activeDiscard.unwrapErr()).code).equal('conflict');
    should(await activeRetention.isErr()).be.true();
    should((await activeRetention.unwrapErr()).code).equal('conflict');
    should((await Promise.all(swaps.map(result => result.isOk()))).filter(Boolean)).have.length(1);
    should(firstCleanup).containEql(firstGeneration);
    should(secondCleanup).containEql(secondGeneration);
    should(await redis.exists(`cfg:${firstGeneration}:landscape`)).equal(0);
    should(await redis.exists(`cfg:${secondGeneration}:landscape`)).equal(0);
    should(await redis.exists(`cfg:${active?.generation}:landscape`)).equal(1);
    should(await redis.zscore('cfg:retained', String(active?.generation))).not.be.null();
  });
});
