import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type {
  AtomicAcceptOutcome,
  AtomicAcceptRequest,
  BeginEventMonthArchiveRequest,
  CircuitStatus,
  Clock,
  DeadLetterEntry,
  DeadLetterPage,
  DeliveryAttempt,
  DeliveryClaimRequest,
  DeliveryJob,
  DeliveryJobClaim,
  EndpointCircuit,
  EventMonthArchiveLease,
  EventMonthArchiveManifest,
  EventMonthArchivePage,
  EventMonthDeletionPage,
  FlowStore,
  LandscapeRuntimeConfig,
  QuotaDecision,
  QuotaRequest,
  RetainedEventPage,
  RetainedEventQuery,
  RuntimeConfigStore,
  StorageFailure,
  WebhookEnvelope,
} from '../domain/index.ts';
import { type EventArchiveRecord, encodeEventArchivePage, eventMonth } from './codec.ts';
import {
  retainedEventLimit,
  retainedEventMatches,
  retainedEventOffset,
  retainedEventRecord,
} from './retained-events.ts';

interface QuotaBucket {
  readonly tokens: number;
  readonly updatedAtMs: number;
}

interface DeliveryLease {
  readonly claimToken: string;
  readonly leasedUntilMs: number;
}

interface MemoryArchiveState {
  readonly version: number;
  readonly phase: 'deleting' | 'exporting' | 'live';
  readonly leaseToken?: string;
  readonly leasedUntilMs?: number;
  readonly snapshotCursor?: string;
  readonly manifest?: EventMonthArchiveManifest;
}

const DLQ_RETENTION_MS = 72 * 60 * 60 * 1_000;
const DEFAULT_PAGE_LIMIT = 100;
const MAX_PAGE_LIMIT = 1_000;

const monthKey = (tenantId: string, month: string): string => `${tenantId}\u0000${month}`;
const endpointKey = (tenantId: string, endpointId: string): string => `${tenantId}\u0000${endpointId}`;

const validPageLimit = (limit: number | undefined): number | null => {
  const normalized = limit ?? DEFAULT_PAGE_LIMIT;
  return Number.isSafeInteger(normalized) && normalized >= 1 && normalized <= MAX_PAGE_LIMIT ? normalized : null;
};

const failure = (operation: string, message: string, code: StorageFailure['code'] = 'unavailable'): StorageFailure => ({
  code,
  operation,
  message,
});

const endpointCircuit = (endpointKey: string): EndpointCircuit => ({
  endpointKey,
  status: 'closed',
});

const copyEnvelope = (envelope: WebhookEnvelope): WebhookEnvelope => ({
  ...structuredClone(envelope),
  rawBody: envelope.rawBody.slice(),
});

const copyJob = (job: DeliveryJob): DeliveryJob => structuredClone(job);

/** Deterministic, landscape-scoped fake implementing the same atomic contract as Redis. */
export class MemoryLandscapeStore implements FlowStore, RuntimeConfigStore {
  readonly configGenerations = new Map<number, LandscapeRuntimeConfig>();
  readonly retainedGenerationDeadlines = new Map<number, number>();
  public activeGeneration: number | null = null;
  public lastReservedGeneration = 0;
  readonly dedupExpiries = new Map<string, number>();
  readonly dedupEventIds = new Map<string, string>();
  readonly events = new Map<string, WebhookEnvelope>();
  readonly jobs = new Map<string, DeliveryJob>();
  readonly deliveryLeases = new Map<string, DeliveryLease>();
  readonly eventJobs = new Map<string, string[]>();
  readonly eventMonthIndexes = new Map<string, string[]>();
  readonly deadLetters = new Map<string, DeadLetterEntry[]>();
  readonly deadLetterStoredAtMs = new WeakMap<DeadLetterEntry, number>();
  readonly deadLetterEndpointJobs = new Map<string, Map<string, number>>();
  readonly pausedExpiries = new Map<string, number>();
  readonly pausedEndpointJobs = new Map<string, Set<string>>();
  readonly archiveStates = new Map<string, MemoryArchiveState>();
  readonly circuits = new Map<string, EndpointCircuit>();
  readonly quotaBuckets = new Map<string, QuotaBucket>();
  readonly queuedFailures = new Map<string, StorageFailure[]>();
  readonly durableEvents: string[] = [];

  constructor(
    readonly landscape: string,
    readonly clock: Clock,
    readonly onDurable?: (eventId: string) => void,
    readonly dlqRetentionMs = DLQ_RETENTION_MS,
  ) {
    if (!Number.isSafeInteger(dlqRetentionMs) || dlqRetentionMs < 1 || dlqRetentionMs > DLQ_RETENTION_MS) {
      throw new RangeError('DLQ retention must be a positive duration no greater than 72 hours');
    }
  }

  failNext(operation: string, message = `${operation} failed`): void {
    const failures = this.queuedFailures.get(operation) ?? [];
    failures.push(failure(operation, message));
    this.queuedFailures.set(operation, failures);
  }

  failureFor(operation: string): StorageFailure | null {
    const failures = this.queuedFailures.get(operation);
    const next = failures?.shift() ?? null;
    if (failures !== undefined && failures.length === 0) {
      this.queuedFailures.delete(operation);
    }
    return next;
  }

  async readActive(): Promise<Result<LandscapeRuntimeConfig | null, StorageFailure>> {
    const injected = this.failureFor('read-config');
    if (injected !== null) {
      return Err(injected);
    }
    if (this.activeGeneration === null) {
      return Ok(null);
    }
    const config = this.configGenerations.get(this.activeGeneration);
    return config === undefined
      ? Err(failure('read-config', 'active generation is incomplete', 'invalid-data'))
      : Ok(structuredClone(config));
  }

  async reserveGeneration(): Promise<Result<number, StorageFailure>> {
    const injected = this.failureFor('reserve-generation');
    if (injected !== null) {
      return Err(injected);
    }
    const knownGeneration = Math.max(
      this.lastReservedGeneration,
      this.activeGeneration ?? 0,
      ...this.configGenerations.keys(),
    );
    this.lastReservedGeneration = knownGeneration + 1;
    return Ok(this.lastReservedGeneration);
  }

  async stage(config: LandscapeRuntimeConfig): Promise<Result<void, StorageFailure>> {
    const injected = this.failureFor('stage-config');
    if (injected !== null) {
      return Err(injected);
    }
    this.configGenerations.set(config.generation, structuredClone(config));
    return Ok(undefined);
  }

  async activate(
    generation: number,
    expectedPreviousGeneration: number | null,
    retainPreviousUntilMs?: number,
  ): Promise<Result<void, StorageFailure>> {
    const injected = this.failureFor('activate-config');
    if (injected !== null) {
      return Err(injected);
    }
    if (!this.configGenerations.has(generation)) {
      return Err(failure('activate-config', 'generation was not fully staged', 'invalid-data'));
    }
    if (this.activeGeneration !== expectedPreviousGeneration) {
      return Err(failure('activate-config', 'active generation changed concurrently', 'conflict'));
    }
    this.activeGeneration = generation;
    this.retainedGenerationDeadlines.delete(generation);
    if (expectedPreviousGeneration !== null && retainPreviousUntilMs !== undefined) {
      this.retainedGenerationDeadlines.set(expectedPreviousGeneration, retainPreviousUntilMs);
    }
    return Ok(undefined);
  }

  async discardExpired(nowMs: number): Promise<Result<readonly number[], StorageFailure>> {
    const discarded: number[] = [];
    for (const [generation, deadlineMs] of this.retainedGenerationDeadlines) {
      if (deadlineMs > nowMs || generation === this.activeGeneration) {
        continue;
      }
      this.configGenerations.delete(generation);
      this.retainedGenerationDeadlines.delete(generation);
      discarded.push(generation);
    }
    return Ok(discarded.sort((left, right) => left - right));
  }

  async retainGeneration(generation: number, untilMs: number): Promise<Result<void, StorageFailure>> {
    if (!Number.isSafeInteger(untilMs) || untilMs < 0) {
      return Err(failure('retain-config', 'generation retention deadline is invalid', 'invalid-data'));
    }
    if (generation === this.activeGeneration) {
      return Err(failure('retain-config', 'active generation cannot be scheduled for retention cleanup', 'conflict'));
    }
    if (!this.configGenerations.has(generation)) {
      return Err(failure('retain-config', 'generation is not staged', 'invalid-data'));
    }
    this.retainedGenerationDeadlines.set(generation, untilMs);
    return Ok(undefined);
  }

  async discard(generation: number): Promise<Result<void, StorageFailure>> {
    if (generation === this.activeGeneration) {
      return Err(failure('discard-config', 'active generation cannot be discarded', 'conflict'));
    }
    this.configGenerations.delete(generation);
    this.retainedGenerationDeadlines.delete(generation);
    return Ok(undefined);
  }

  async consumeQuota(request: QuotaRequest): Promise<Result<QuotaDecision, StorageFailure>> {
    const injected = this.failureFor('consume-quota');
    if (injected !== null) {
      return Err(injected);
    }
    if (request.ratePerSecond <= 0 || request.burst <= 0) {
      return Err(failure('consume-quota', 'quota rate and burst must be positive', 'invalid-data'));
    }

    const previous = this.quotaBuckets.get(request.tenantId) ?? {
      tokens: request.burst,
      updatedAtMs: request.nowMs,
    };
    const elapsedMs = Math.max(0, request.nowMs - previous.updatedAtMs);
    const refilled = Math.min(request.burst, previous.tokens + (elapsedMs * request.ratePerSecond) / 1_000);
    if (refilled < 1) {
      const retryAfterSeconds = Math.max(1, Math.ceil((1 - refilled) / request.ratePerSecond));
      this.quotaBuckets.set(request.tenantId, {
        tokens: refilled,
        updatedAtMs: request.nowMs,
      });
      return Ok({ allowed: false, retryAfterSeconds });
    }

    this.quotaBuckets.set(request.tenantId, {
      tokens: refilled - 1,
      updatedAtMs: request.nowMs,
    });
    return Ok({ allowed: true, retryAfterSeconds: 0 });
  }

  async acceptOnce(request: AtomicAcceptRequest): Promise<Result<AtomicAcceptOutcome, StorageFailure>> {
    const injected = this.failureFor('accept-once');
    if (injected !== null) {
      return Err(injected);
    }

    const nowMs = this.clock.nowMs();
    const expiry = this.dedupExpiries.get(request.dedupKey);
    if (expiry !== undefined && expiry > nowMs) {
      const eventId = this.dedupEventIds.get(request.dedupKey);
      return eventId === undefined
        ? Err(failure('accept-once', 'dedup claim is missing its accepted event', 'invalid-data'))
        : Ok({ kind: 'duplicate', eventId });
    }
    if (expiry !== undefined) {
      this.dedupExpiries.delete(request.dedupKey);
      this.dedupEventIds.delete(request.dedupKey);
    }

    const jobIds = request.jobs.map(job => job.id);
    const obligationIds = request.envelope.obligations.map(obligation => obligation.id);
    if (
      !Number.isSafeInteger(request.dedupTtlSeconds) ||
      request.dedupTtlSeconds < 1 ||
      new Set(jobIds).size !== jobIds.length ||
      jobIds.length !== obligationIds.length ||
      jobIds.some(jobId => !obligationIds.includes(jobId))
    ) {
      return Err(
        failure(
          'accept-once',
          'dedup TTL must be positive and jobs must match endpoint obligations one-for-one',
          'invalid-data',
        ),
      );
    }
    if (this.events.has(request.envelope.id) || request.jobs.some(job => this.jobs.has(job.id))) {
      return Err(failure('accept-once', 'event or job id already exists', 'conflict'));
    }

    const month = eventMonth(request.envelope.receivedAtMs);
    const archiveKey = monthKey(request.envelope.tenantId, month);
    const archiveState = this.archiveStates.get(archiveKey);
    if (archiveState?.phase === 'deleting') {
      return Err(failure('accept-once', 'event month is sealed for archive deletion', 'conflict'));
    }
    if (archiveState?.phase === 'exporting' && (archiveState.leasedUntilMs ?? Number.POSITIVE_INFINITY) > nowMs) {
      return Err(failure('accept-once', 'event month is leased for archive export', 'conflict'));
    }

    const envelope = copyEnvelope(request.envelope);
    const jobs = request.jobs.map(copyJob);
    this.dedupExpiries.set(request.dedupKey, nowMs + request.dedupTtlSeconds * 1_000);
    this.dedupEventIds.set(request.dedupKey, envelope.id);
    this.events.set(envelope.id, envelope);
    this.eventJobs.set(
      envelope.id,
      jobs.map(job => job.id),
    );
    for (const job of jobs) {
      this.jobs.set(job.id, job);
    }
    const monthEvents = this.eventMonthIndexes.get(archiveKey) ?? [];
    monthEvents.push(envelope.id);
    this.eventMonthIndexes.set(archiveKey, monthEvents);
    this.archiveStates.set(archiveKey, {
      phase: 'live',
      version: (archiveState?.version ?? 0) + 1,
    });
    this.durableEvents.push(envelope.id);
    this.onDurable?.(envelope.id);
    return Ok({ kind: 'accepted', eventId: envelope.id });
  }

  async acknowledgeEvent(eventId: string, acknowledgedAtMs: number): Promise<Result<void, StorageFailure>> {
    const injected = this.failureFor('acknowledge-event');
    if (injected !== null) {
      return Err(injected);
    }
    if (!Number.isSafeInteger(acknowledgedAtMs) || acknowledgedAtMs < 0) {
      return Err(failure('acknowledge-event', 'acknowledgement timestamp is invalid', 'invalid-data'));
    }
    const current = this.events.get(eventId);
    if (current === undefined) {
      return Err(failure('acknowledge-event', 'accepted event not found', 'invalid-data'));
    }
    if (current.acknowledgedAtMs === undefined) {
      this.events.set(eventId, { ...current, acknowledgedAtMs });
    }
    return Ok(undefined);
  }

  async getEvent(eventId: string): Promise<Result<WebhookEnvelope | null, StorageFailure>> {
    const event = this.events.get(eventId);
    return Ok(event === undefined ? null : copyEnvelope(event));
  }

  async getJob(jobId: string): Promise<Result<DeliveryJob | null, StorageFailure>> {
    const job = this.jobs.get(jobId);
    return Ok(job === undefined ? null : copyJob(job));
  }

  async listEventJobs(eventId: string): Promise<Result<readonly DeliveryJob[], StorageFailure>> {
    const jobs = (this.eventJobs.get(eventId) ?? [])
      .map(jobId => this.jobs.get(jobId))
      .filter((job): job is DeliveryJob => job !== undefined)
      .map(copyJob);
    return Ok(jobs);
  }

  async listRetainedEvents(query: RetainedEventQuery): Promise<Result<RetainedEventPage, StorageFailure>> {
    const offset = retainedEventOffset(query.cursor);
    const limit = retainedEventLimit(query.limit);
    if (offset === null || limit === null) {
      return Err(failure('list-retained-events', 'invalid retained-event cursor or limit', 'invalid-data'));
    }

    const ordered = [...this.events.values()]
      .filter(event => event.tenantId === query.tenantId)
      .sort((left, right) => right.receivedAtMs - left.receivedAtMs || left.id.localeCompare(right.id));
    const items = [];
    let index = offset;
    while (index < ordered.length && items.length < limit) {
      const envelope = ordered[index];
      index += 1;
      if (envelope === undefined) {
        continue;
      }
      const jobs = (this.eventJobs.get(envelope.id) ?? [])
        .map(jobId => this.jobs.get(jobId))
        .filter((job): job is DeliveryJob => job !== undefined)
        .map(copyJob);
      const record = retainedEventRecord(copyEnvelope(envelope), jobs);
      if (retainedEventMatches(record, query)) {
        items.push(record);
      }
    }

    return Ok({
      items,
      ...(index < ordered.length ? { nextCursor: String(index) } : {}),
    });
  }

  async claimDueJobs(request: DeliveryClaimRequest): Promise<Result<readonly DeliveryJobClaim[], StorageFailure>> {
    const validated = this.validateClaimRequest(request);
    if (validated !== null) {
      return Err(validated);
    }
    this.expireDeliveryLeases(request.nowMs);
    const limit = request.limit ?? 100;
    const due = [...this.jobs.values()]
      .filter(
        job =>
          job.status === 'pending' &&
          job.dueAtMs <= request.nowMs &&
          this.events.get(job.eventId)?.acknowledgedAtMs !== undefined &&
          !this.deliveryLeases.has(job.id),
      )
      .sort((left, right) => left.dueAtMs - right.dueAtMs || left.id.localeCompare(right.id))
      .slice(0, limit);
    const leasedUntilMs = request.nowMs + request.leaseMs;
    return Ok(
      due.map(job => {
        this.deliveryLeases.set(job.id, {
          claimToken: request.claimToken,
          leasedUntilMs,
        });
        return {
          claimToken: request.claimToken,
          job: copyJob(job),
          leasedUntilMs,
        };
      }),
    );
  }

  async claimJob(
    jobId: string,
    request: Omit<DeliveryClaimRequest, 'limit'>,
  ): Promise<Result<DeliveryJobClaim | null, StorageFailure>> {
    const validated = this.validateClaimRequest(request);
    if (validated !== null) {
      return Err(validated);
    }
    this.expireDeliveryLeases(request.nowMs);
    const job = this.jobs.get(jobId);
    if (
      job === undefined ||
      job.status === 'completed' ||
      job.status === 'dead-letter' ||
      this.events.get(job.eventId)?.acknowledgedAtMs === undefined ||
      this.deliveryLeases.has(jobId)
    ) {
      return Ok(null);
    }
    const leasedUntilMs = request.nowMs + request.leaseMs;
    this.deliveryLeases.set(jobId, {
      claimToken: request.claimToken,
      leasedUntilMs,
    });
    return Ok({
      claimToken: request.claimToken,
      job: copyJob(job),
      leasedUntilMs,
    });
  }

  async releaseJobClaim(jobId: string, claimToken: string): Promise<Result<void, StorageFailure>> {
    const ownership = this.assertClaimOwnership(jobId, claimToken);
    if (ownership !== null) {
      return Err(ownership);
    }
    this.deliveryLeases.delete(jobId);
    return Ok(undefined);
  }

  async recordAttempt(
    jobId: string,
    attempt: DeliveryAttempt,
    claimToken?: string,
  ): Promise<Result<DeliveryJob, StorageFailure>> {
    const ownership = this.assertClaimOwnership(jobId, claimToken);
    if (ownership !== null) {
      return Err(ownership);
    }
    const current = this.jobs.get(jobId);
    if (current === undefined) {
      return Err(failure('record-attempt', 'delivery job not found', 'invalid-data'));
    }
    const updated: DeliveryJob = {
      ...current,
      attempts: [...current.attempts, structuredClone(attempt)],
    };
    this.jobs.set(jobId, updated);
    return Ok(copyJob(updated));
  }

  async completeJob(jobId: string, claimToken?: string): Promise<Result<DeliveryJob, StorageFailure>> {
    const ownership = this.assertClaimOwnership(jobId, claimToken);
    if (ownership !== null) {
      return Err(ownership);
    }
    const current = this.jobs.get(jobId);
    if (current === undefined) {
      return Err(failure('complete-job', 'delivery job not found', 'invalid-data'));
    }
    const updated: DeliveryJob = { ...current, status: 'completed' };
    this.jobs.set(jobId, updated);
    this.deliveryLeases.delete(jobId);
    this.removePausedJobIndexes(current);
    this.removeDeadLetterEndpointIndex(current);
    return Ok(copyJob(updated));
  }

  async scheduleJob(
    jobId: string,
    dueAtMs: number,
    address?: string,
    misrouteRefreshes?: number,
    claimToken?: string,
    retainClaim = false,
  ): Promise<Result<DeliveryJob, StorageFailure>> {
    const ownership = this.assertClaimOwnership(jobId, claimToken);
    if (ownership !== null) {
      return Err(ownership);
    }
    const current = this.jobs.get(jobId);
    if (current === undefined) {
      return Err(failure('schedule-job', 'delivery job not found', 'invalid-data'));
    }
    const updated: DeliveryJob = {
      ...current,
      dueAtMs,
      status: 'pending',
      ...(address === undefined ? {} : { address }),
      ...(misrouteRefreshes === undefined ? {} : { misrouteRefreshes }),
    };
    this.jobs.set(jobId, updated);
    this.removePausedJobIndexes(current);
    this.removeDeadLetterEndpointIndex(current);
    if (!retainClaim) {
      this.deliveryLeases.delete(jobId);
    }
    return Ok(copyJob(updated));
  }

  async pauseJob(jobId: string, claimToken?: string): Promise<Result<DeliveryJob, StorageFailure>> {
    const ownership = this.assertClaimOwnership(jobId, claimToken);
    if (ownership !== null) {
      return Err(ownership);
    }
    const current = this.jobs.get(jobId);
    if (current === undefined) {
      return Err(failure('pause-job', 'delivery job not found', 'invalid-data'));
    }
    const updated: DeliveryJob = { ...current, status: 'paused' };
    this.jobs.set(jobId, updated);
    this.deliveryLeases.delete(jobId);
    this.removeDeadLetterEndpointIndex(current);
    this.indexPausedJob(updated);
    return Ok(copyJob(updated));
  }

  async expirePausedJobs(nowMs: number, limit?: number): Promise<Result<readonly DeadLetterEntry[], StorageFailure>> {
    const boundedLimit = validPageLimit(limit);
    if (!Number.isSafeInteger(nowMs) || nowMs < 0 || boundedLimit === null) {
      return Err(failure('expire-paused-jobs', 'invalid paused-expiry request', 'invalid-data'));
    }
    const due = [...this.pausedExpiries]
      .filter(([, expiresAtMs]) => expiresAtMs <= nowMs)
      .sort((left, right) => left[1] - right[1] || left[0].localeCompare(right[0]))
      .slice(0, boundedLimit);
    const expired: DeadLetterEntry[] = [];
    for (const [jobId] of due) {
      const current = this.jobs.get(jobId);
      if (current === undefined || current.status !== 'paused') {
        if (current !== undefined) {
          this.removePausedJobIndexes(current);
        } else {
          this.pausedExpiries.delete(jobId);
        }
        continue;
      }
      const transitioned = await this.deadLetter(jobId, nowMs, 'retry-window-expired');
      if (await transitioned.isErr()) {
        return Err(await transitioned.unwrapErr());
      }
      expired.push(await transitioned.unwrap());
    }
    return Ok(expired);
  }

  async resumeEndpoint(
    tenantId: string,
    endpointId: string,
    nowMs: number,
  ): Promise<Result<readonly DeliveryJob[], StorageFailure>> {
    const indexedIds = [...(this.pausedEndpointJobs.get(endpointKey(tenantId, endpointId)) ?? [])];
    const candidates = indexedIds
      .map(jobId => this.jobs.get(jobId))
      .filter((job): job is DeliveryJob => job !== undefined && job.status === 'paused');
    const months = new Set<string>();
    for (const current of candidates) {
      if (this.deliveryLeases.has(current.id)) {
        return Err(failure('resume-endpoint', 'paused job has an active delivery claim', 'conflict'));
      }
      const month = this.eventMonthForJob(current);
      const blocked = this.ensureMonthMutable(current.tenantId, month, nowMs, 'resume-endpoint');
      if (blocked !== null) {
        return Err(blocked);
      }
      months.add(month);
    }
    const resumed: DeliveryJob[] = [];
    for (const current of candidates) {
      const updated: DeliveryJob = {
        ...current,
        dueAtMs: nowMs,
        status: 'pending',
      };
      this.jobs.set(current.id, updated);
      this.removePausedJobIndexes(current);
      this.removeDeadLetterEndpointIndex(current);
      resumed.push(copyJob(updated));
    }
    for (const month of months) {
      this.advanceMonthVersion(tenantId, month);
    }
    return Ok(resumed);
  }

  async deadLetter(
    jobId: string,
    exhaustedAtMs: number,
    reason: string,
    claimToken?: string,
  ): Promise<Result<DeadLetterEntry, StorageFailure>> {
    if (!Number.isSafeInteger(exhaustedAtMs) || exhaustedAtMs < 0 || reason.trim().length === 0) {
      return Err(failure('dead-letter', 'invalid dead-letter transition', 'invalid-data'));
    }
    const ownership = this.assertClaimOwnership(jobId, claimToken);
    if (ownership !== null) {
      return Err(ownership);
    }
    const current = this.jobs.get(jobId);
    if (current === undefined) {
      return Err(failure('dead-letter', 'delivery job not found', 'invalid-data'));
    }
    const updated: DeliveryJob = { ...current, status: 'dead-letter' };
    this.jobs.set(jobId, updated);
    this.deliveryLeases.delete(jobId);
    this.removePausedJobIndexes(current);
    const entry: DeadLetterEntry = {
      landscape: this.landscape,
      tenantId: current.tenantId,
      eventId: current.eventId,
      endpointId: current.endpointId,
      jobId,
      exhaustedAtMs,
      reason,
    };
    const storedAtMs = this.clock.nowMs();
    this.pruneDeadLetters(current.tenantId, storedAtMs);
    const entries = this.deadLetters.get(current.tenantId) ?? [];
    entries.push(entry);
    this.deadLetterStoredAtMs.set(entry, storedAtMs);
    this.deadLetters.set(current.tenantId, entries);
    this.indexDeadLetterEndpoint(entry, storedAtMs);
    return Ok(structuredClone(entry));
  }

  private indexPausedJob(job: DeliveryJob): void {
    this.pausedExpiries.set(job.id, job.createdAtMs + job.retryWindowMs);
    const key = endpointKey(job.tenantId, job.endpointId);
    const jobs = this.pausedEndpointJobs.get(key) ?? new Set<string>();
    jobs.add(job.id);
    this.pausedEndpointJobs.set(key, jobs);
  }

  private removePausedJobIndexes(job: DeliveryJob): void {
    this.pausedExpiries.delete(job.id);
    const key = endpointKey(job.tenantId, job.endpointId);
    const jobs = this.pausedEndpointJobs.get(key);
    jobs?.delete(job.id);
    if (jobs?.size === 0) {
      this.pausedEndpointJobs.delete(key);
    }
  }

  private indexDeadLetterEndpoint(entry: DeadLetterEntry, storedAtMs: number): void {
    const key = endpointKey(entry.tenantId, entry.endpointId);
    const jobs = this.deadLetterEndpointJobs.get(key) ?? new Map<string, number>();
    jobs.set(entry.jobId, storedAtMs);
    this.deadLetterEndpointJobs.set(key, jobs);
  }

  private removeDeadLetterEndpointIndex(job: DeliveryJob): void {
    const key = endpointKey(job.tenantId, job.endpointId);
    const jobs = this.deadLetterEndpointJobs.get(key);
    jobs?.delete(job.id);
    if (jobs?.size === 0) {
      this.deadLetterEndpointJobs.delete(key);
    }
  }

  private pruneDeadLetters(tenantId: string, nowMs: number): void {
    const cutoffMs = nowMs - this.dlqRetentionMs;
    const retained = (this.deadLetters.get(tenantId) ?? []).filter(entry => {
      const storedAtMs = this.deadLetterStoredAtMs.get(entry) ?? entry.exhaustedAtMs;
      if (storedAtMs > cutoffMs) {
        return true;
      }
      const indexed = this.deadLetterEndpointJobs.get(endpointKey(entry.tenantId, entry.endpointId));
      if (indexed?.get(entry.jobId) === storedAtMs) {
        indexed.delete(entry.jobId);
        if (indexed.size === 0) {
          this.deadLetterEndpointJobs.delete(endpointKey(entry.tenantId, entry.endpointId));
        }
      }
      return false;
    });
    if (retained.length === 0) {
      this.deadLetters.delete(tenantId);
    } else {
      this.deadLetters.set(tenantId, retained);
    }
  }

  private ensureMonthMutable(tenantId: string, month: string, nowMs: number, operation: string): StorageFailure | null {
    const key = monthKey(tenantId, month);
    const state = this.archiveStates.get(key);
    if (state?.phase === 'deleting') {
      return failure(operation, 'event month is sealed for archive deletion', 'conflict');
    }
    if (state?.phase === 'exporting') {
      if ((state.leasedUntilMs ?? Number.POSITIVE_INFINITY) > nowMs) {
        return failure(operation, 'event month is leased for archive export', 'conflict');
      }
      this.archiveStates.set(key, { phase: 'live', version: state.version });
    }
    return null;
  }

  private eventMonthForJob(job: DeliveryJob): string {
    return eventMonth(this.events.get(job.eventId)?.receivedAtMs ?? job.createdAtMs);
  }

  private advanceMonthVersion(tenantId: string, month: string): void {
    const key = monthKey(tenantId, month);
    const state = this.archiveStates.get(key);
    this.archiveStates.set(key, {
      phase: 'live',
      version: (state?.version ?? 0) + 1,
    });
  }

  private validateClaimRequest(
    request: Omit<DeliveryClaimRequest, 'limit'> & { readonly limit?: number },
  ): StorageFailure | null {
    if (
      request.claimToken.length === 0 ||
      !Number.isSafeInteger(request.nowMs) ||
      request.nowMs < 0 ||
      !Number.isSafeInteger(request.leaseMs) ||
      request.leaseMs < 1 ||
      (request.limit !== undefined &&
        (!Number.isSafeInteger(request.limit) || request.limit < 1 || request.limit > 1_000))
    ) {
      return failure('claim-delivery', 'invalid delivery claim request', 'invalid-data');
    }
    return null;
  }

  private expireDeliveryLeases(nowMs: number): void {
    for (const [jobId, lease] of this.deliveryLeases) {
      if (lease.leasedUntilMs <= nowMs) {
        this.deliveryLeases.delete(jobId);
      }
    }
  }

  private assertClaimOwnership(jobId: string, claimToken: string | undefined): StorageFailure | null {
    this.expireDeliveryLeases(this.clock.nowMs());
    const lease = this.deliveryLeases.get(jobId);
    if ((lease === undefined && claimToken === undefined) || (lease !== undefined && lease.claimToken === claimToken)) {
      return null;
    }
    return failure('delivery-transition', 'delivery claim is missing, expired, or owned by another worker', 'conflict');
  }

  async listDeadLetters(tenantId: string): Promise<Result<readonly DeadLetterEntry[], StorageFailure>> {
    const page = await this.listDeadLetterPage(tenantId);
    return (await page.isErr()) ? Err(await page.unwrapErr()) : Ok((await page.unwrap()).items);
  }

  async listDeadLetterPage(
    tenantId: string,
    cursor?: string,
    limit?: number,
  ): Promise<Result<DeadLetterPage, StorageFailure>> {
    const boundedLimit = validPageLimit(limit);
    const offset = cursor === undefined ? 0 : Number(cursor);
    if (boundedLimit === null || !Number.isSafeInteger(offset) || offset < 0) {
      return Err(failure('list-dead-letters', 'invalid dead-letter cursor or limit', 'invalid-data'));
    }
    this.pruneDeadLetters(tenantId, this.clock.nowMs());
    // Stable fake ordering is an implementation detail; the FlowStore cursor contract is opaque.
    const ordered = [...(this.deadLetters.get(tenantId) ?? [])].sort(
      (left, right) => right.exhaustedAtMs - left.exhaustedAtMs || left.jobId.localeCompare(right.jobId),
    );
    const items = ordered.slice(offset, offset + boundedLimit).map(entry => structuredClone(entry));
    const nextOffset = offset + items.length;
    return Ok({
      items,
      ...(nextOffset < ordered.length ? { nextCursor: String(nextOffset) } : {}),
    });
  }

  async replayEvent(eventId: string, nowMs: number): Promise<Result<readonly DeliveryJob[], StorageFailure>> {
    const ids = this.eventJobs.get(eventId);
    if (ids === undefined) {
      return Err(failure('replay-event', 'event not found', 'invalid-data'));
    }
    const currentJobs = ids.map(id => this.jobs.get(id)).filter((job): job is DeliveryJob => job !== undefined);
    const months = new Set<string>();
    for (const current of currentJobs) {
      if (this.deliveryLeases.has(current.id)) {
        return Err(failure('replay-event', 'delivery job has an active claim', 'conflict'));
      }
      const month = this.eventMonthForJob(current);
      const blocked = this.ensureMonthMutable(current.tenantId, month, nowMs, 'replay-event');
      if (blocked !== null) {
        return Err(blocked);
      }
      months.add(month);
    }
    const replayed: DeliveryJob[] = [];
    for (const current of currentJobs) {
      const updated: DeliveryJob = {
        ...current,
        createdAtMs: nowMs,
        dueAtMs: nowMs,
        status: 'pending',
        replayCount: current.replayCount + 1,
      };
      this.jobs.set(current.id, updated);
      this.removePausedJobIndexes(current);
      this.removeDeadLetterEndpointIndex(current);
      replayed.push(copyJob(updated));
    }
    for (const month of months) {
      this.advanceMonthVersion(currentJobs[0]?.tenantId ?? '', month);
    }
    return Ok(replayed);
  }

  async replayEndpoint(
    eventId: string,
    endpointId: string,
    nowMs: number,
  ): Promise<Result<DeliveryJob, StorageFailure>> {
    const jobsResult = await this.listEventJobs(eventId);
    const current = (await jobsResult.unwrap()).find(job => job.endpointId === endpointId);
    if (current === undefined) {
      return Err(failure('replay-endpoint', 'event endpoint obligation not found', 'invalid-data'));
    }
    if (this.deliveryLeases.has(current.id)) {
      return Err(failure('replay-endpoint', 'delivery job has an active claim', 'conflict'));
    }
    const month = this.eventMonthForJob(current);
    const blocked = this.ensureMonthMutable(current.tenantId, month, nowMs, 'replay-endpoint');
    if (blocked !== null) {
      return Err(blocked);
    }
    const updated: DeliveryJob = {
      ...current,
      createdAtMs: nowMs,
      dueAtMs: nowMs,
      status: 'pending',
      replayCount: current.replayCount + 1,
    };
    this.jobs.set(current.id, updated);
    this.removePausedJobIndexes(current);
    this.removeDeadLetterEndpointIndex(current);
    this.advanceMonthVersion(current.tenantId, month);
    return Ok(copyJob(updated));
  }

  async replayDeadLettersForEndpoint(
    tenantId: string,
    endpointId: string,
    nowMs: number,
  ): Promise<Result<readonly DeliveryJob[], StorageFailure>> {
    this.pruneDeadLetters(tenantId, this.clock.nowMs());
    const indexKey = endpointKey(tenantId, endpointId);
    const indexed = this.deadLetterEndpointJobs.get(indexKey);
    if (indexed === undefined) {
      return Ok([]);
    }
    let inspected = 0;
    while (inspected < MAX_PAGE_LIMIT) {
      const candidateIds = [...indexed]
        .sort((left, right) => left[1] - right[1] || left[0].localeCompare(right[0]))
        .slice(0, DEFAULT_PAGE_LIMIT)
        .map(([jobId]) => jobId);
      if (candidateIds.length === 0) {
        this.deadLetterEndpointJobs.delete(indexKey);
        return Ok([]);
      }
      inspected += candidateIds.length;
      const candidates: DeliveryJob[] = [];
      for (const jobId of candidateIds) {
        const job = this.jobs.get(jobId);
        if (
          job === undefined ||
          job.status !== 'dead-letter' ||
          job.tenantId !== tenantId ||
          job.endpointId !== endpointId
        ) {
          indexed.delete(jobId);
          continue;
        }
        candidates.push(job);
      }
      if (indexed.size === 0) {
        this.deadLetterEndpointJobs.delete(indexKey);
      }
      if (candidates.length === 0) {
        continue;
      }
      const months = new Set<string>();
      for (const current of candidates) {
        if (this.deliveryLeases.has(current.id)) {
          return Err(failure('replay-endpoint-dead-letters', 'delivery job has an active claim', 'conflict'));
        }
        const month = this.eventMonthForJob(current);
        const blocked = this.ensureMonthMutable(current.tenantId, month, nowMs, 'replay-endpoint-dead-letters');
        if (blocked !== null) {
          return Err(blocked);
        }
        months.add(month);
      }
      const replayed: DeliveryJob[] = [];
      for (const current of candidates) {
        const updated: DeliveryJob = {
          ...current,
          createdAtMs: nowMs,
          dueAtMs: nowMs,
          status: 'pending',
          replayCount: current.replayCount + 1,
        };
        this.jobs.set(current.id, updated);
        this.removePausedJobIndexes(current);
        this.removeDeadLetterEndpointIndex(current);
        replayed.push(copyJob(updated));
      }
      for (const month of months) {
        this.advanceMonthVersion(tenantId, month);
      }
      return Ok(replayed);
    }
    return Ok([]);
  }

  async getCircuit(endpointKey: string): Promise<Result<EndpointCircuit, StorageFailure>> {
    return Ok(structuredClone(this.circuits.get(endpointKey) ?? endpointCircuit(endpointKey)));
  }

  async recordEndpointFailure(
    endpointKey: string,
    nowMs: number,
    openAfterMs: number,
  ): Promise<Result<EndpointCircuit, StorageFailure>> {
    const current = this.circuits.get(endpointKey) ?? endpointCircuit(endpointKey);
    const firstFailureAtMs = current.firstFailureAtMs ?? nowMs;
    const shouldOpen = current.status === 'open' || nowMs - firstFailureAtMs >= openAfterMs;
    const updated: EndpointCircuit = {
      endpointKey,
      status: shouldOpen ? 'open' : 'closed',
      firstFailureAtMs,
      lastFailureAtMs: nowMs,
      ...(shouldOpen ? { openedAtMs: current.openedAtMs ?? nowMs } : {}),
    };
    this.circuits.set(endpointKey, updated);
    return Ok(structuredClone(updated));
  }

  async closeCircuit(endpointKey: string): Promise<Result<EndpointCircuit, StorageFailure>> {
    const updated = endpointCircuit(endpointKey);
    this.circuits.set(endpointKey, updated);
    return Ok(structuredClone(updated));
  }

  async setCircuitStatus(
    endpointKey: string,
    status: CircuitStatus,
    nowMs: number,
  ): Promise<Result<EndpointCircuit, StorageFailure>> {
    if (status === 'closed') {
      return this.closeCircuit(endpointKey);
    }
    const current = this.circuits.get(endpointKey) ?? endpointCircuit(endpointKey);
    const updated: EndpointCircuit = {
      ...current,
      endpointKey,
      status: 'open',
      firstFailureAtMs: current.firstFailureAtMs ?? nowMs,
      lastFailureAtMs: current.lastFailureAtMs ?? nowMs,
      openedAtMs: current.openedAtMs ?? nowMs,
    };
    this.circuits.set(endpointKey, updated);
    return Ok(structuredClone(updated));
  }

  async listEventMonths(tenantId: string): Promise<Result<readonly string[], StorageFailure>> {
    const prefix = `${tenantId}\u0000`;
    return Ok(
      [...this.eventMonthIndexes]
        .filter(([key, eventIds]) => key.startsWith(prefix) && eventIds.length > 0)
        .map(([key]) => key.slice(prefix.length))
        .sort(),
    );
  }

  async beginEventMonthArchive(
    request: BeginEventMonthArchiveRequest,
  ): Promise<Result<EventMonthArchiveLease, StorageFailure>> {
    if (
      !/^\d{4}-(?:0[1-9]|1[0-2])$/.test(request.month) ||
      request.leaseToken.length === 0 ||
      !Number.isSafeInteger(request.nowMs) ||
      request.nowMs < 0 ||
      !Number.isSafeInteger(request.leaseMs) ||
      request.leaseMs < 1
    ) {
      return Err(failure('begin-event-month-archive', 'invalid archive lease request', 'invalid-data'));
    }
    const key = monthKey(request.tenantId, request.month);
    const eventIds = this.eventMonthIndexes.get(key) ?? [];
    if (eventIds.length === 0) {
      return Err(failure('begin-event-month-archive', 'event month not found', 'invalid-data'));
    }
    const active = eventIds.some(eventId =>
      (this.eventJobs.get(eventId) ?? []).some(jobId => {
        const status = this.jobs.get(jobId)?.status;
        return status === 'paused' || status === 'pending';
      }),
    );
    if (active) {
      return Err(failure('begin-event-month-archive', 'event month still has active obligations', 'conflict'));
    }

    const previous = this.archiveStates.get(key) ?? { phase: 'live' as const, version: 0 };
    if (
      previous.phase !== 'live' &&
      previous.leaseToken !== request.leaseToken &&
      (previous.leasedUntilMs ?? Number.POSITIVE_INFINITY) > request.nowMs
    ) {
      return Err(failure('begin-event-month-archive', 'event month already has an active archive lease', 'conflict'));
    }
    const phase = previous.phase === 'deleting' ? 'deleting' : 'exporting';
    const next: MemoryArchiveState = {
      phase,
      version: previous.version,
      leaseToken: request.leaseToken,
      leasedUntilMs: request.nowMs + request.leaseMs,
      snapshotCursor: previous.snapshotCursor ?? String(eventIds.length),
      ...(previous.manifest === undefined ? {} : { manifest: previous.manifest }),
    };
    this.archiveStates.set(key, next);
    return Ok({
      tenantId: request.tenantId,
      month: request.month,
      leaseToken: request.leaseToken,
      version: next.version,
      leasedUntilMs: next.leasedUntilMs ?? 0,
      snapshotCursor: next.snapshotCursor ?? '0',
      phase,
      ...(next.manifest === undefined ? {} : { manifest: next.manifest }),
    });
  }

  async renewEventMonthArchive(
    lease: EventMonthArchiveLease,
    nowMs: number,
    leaseMs: number,
  ): Promise<Result<EventMonthArchiveLease, StorageFailure>> {
    if (!Number.isSafeInteger(nowMs) || nowMs < 0 || !Number.isSafeInteger(leaseMs) || leaseMs < 1) {
      return Err(failure('renew-event-month-archive', 'invalid archive lease renewal', 'invalid-data'));
    }
    const key = monthKey(lease.tenantId, lease.month);
    const state = this.archiveStates.get(key);
    if (
      state === undefined ||
      state.phase !== lease.phase ||
      state.version !== lease.version ||
      state.leaseToken !== lease.leaseToken ||
      (state.leasedUntilMs ?? -1) < nowMs
    ) {
      return Err(failure('renew-event-month-archive', 'archive lease is stale or expired', 'conflict'));
    }
    const leasedUntilMs = nowMs + leaseMs;
    this.archiveStates.set(key, { ...state, leasedUntilMs });
    return Ok({ ...lease, leasedUntilMs });
  }

  async readEventMonthArchivePage(
    lease: EventMonthArchiveLease,
    cursor: string | undefined,
    limit: number,
    maxBytes: number,
  ): Promise<Result<EventMonthArchivePage, StorageFailure>> {
    const offset = cursor === undefined ? 0 : Number(cursor);
    if (
      lease.phase !== 'exporting' ||
      !Number.isSafeInteger(offset) ||
      offset < 0 ||
      validPageLimit(limit) === null ||
      !Number.isSafeInteger(maxBytes) ||
      maxBytes < 1
    ) {
      return Err(failure('read-event-month-archive-page', 'invalid archive page request', 'invalid-data'));
    }
    const key = monthKey(lease.tenantId, lease.month);
    const state = this.archiveStates.get(key);
    if (
      state?.phase !== 'exporting' ||
      state.version !== lease.version ||
      state.leaseToken !== lease.leaseToken ||
      (state.leasedUntilMs ?? -1) < this.clock.nowMs()
    ) {
      return Err(failure('read-event-month-archive-page', 'archive lease is stale or expired', 'conflict'));
    }
    const snapshotLength = Number(state.snapshotCursor ?? lease.snapshotCursor);
    const eventIds = this.eventMonthIndexes.get(key) ?? [];
    const records: EventArchiveRecord[] = [];
    let nextOffset = offset;
    let body = encodeEventArchivePage(this.landscape, lease.tenantId, lease.month, lease.version, records);
    while (nextOffset < snapshotLength && records.length < limit) {
      const eventId = eventIds[nextOffset];
      if (eventId === undefined) {
        break;
      }
      const envelope = this.events.get(eventId);
      if (envelope === undefined) {
        return Err(failure('read-event-month-archive-page', 'archive event is missing', 'invalid-data'));
      }
      const jobs = (this.eventJobs.get(eventId) ?? [])
        .map(jobId => this.jobs.get(jobId))
        .filter((job): job is DeliveryJob => job !== undefined)
        .map(copyJob);
      const deadLetters = (this.deadLetters.get(lease.tenantId) ?? [])
        .filter(entry => entry.eventId === eventId)
        .map(entry => structuredClone(entry));
      const record: EventArchiveRecord = { envelope: copyEnvelope(envelope), jobs, deadLetters };
      const candidate: EventArchiveRecord[] = [...records, record];
      const encoded = encodeEventArchivePage(this.landscape, lease.tenantId, lease.month, lease.version, candidate);
      if (encoded.byteLength > maxBytes) {
        if (records.length === 0) {
          return Err(
            failure(
              'read-event-month-archive-page',
              'one archive record exceeds the configured part bound',
              'invalid-data',
            ),
          );
        }
        break;
      }
      records.push(record);
      body = encoded;
      nextOffset += 1;
    }
    const jobCount = records.reduce((total, record) => total + (record?.jobs.length ?? 0), 0);
    const deadLetterCount = records.reduce((total, record) => total + (record?.deadLetters.length ?? 0), 0);
    return Ok({
      body,
      eventCount: records.length,
      jobCount,
      deadLetterCount,
      ...(records.length === 0 ? {} : { firstCursor: String(offset), lastCursor: String(nextOffset - 1) }),
      ...(nextOffset < snapshotLength ? { nextCursor: String(nextOffset) } : {}),
    });
  }

  async sealEventMonthArchive(
    lease: EventMonthArchiveLease,
    manifest: EventMonthArchiveManifest,
  ): Promise<Result<EventMonthArchiveLease, StorageFailure>> {
    const key = monthKey(lease.tenantId, lease.month);
    const state = this.archiveStates.get(key);
    if (
      state?.phase !== 'exporting' ||
      state.version !== lease.version ||
      state.leaseToken !== lease.leaseToken ||
      (state.leasedUntilMs ?? -1) < this.clock.nowMs()
    ) {
      return Err(failure('seal-event-month-archive', 'archive lease is stale or expired', 'conflict'));
    }
    const sealed: MemoryArchiveState = { ...state, phase: 'deleting', manifest };
    this.archiveStates.set(key, sealed);
    return Ok({ ...lease, phase: 'deleting', manifest });
  }

  async deleteEventMonthArchivePage(
    lease: EventMonthArchiveLease,
    limit: number,
  ): Promise<Result<EventMonthDeletionPage, StorageFailure>> {
    const boundedLimit = validPageLimit(limit);
    if (lease.phase !== 'deleting' || boundedLimit === null) {
      return Err(failure('delete-event-month-archive-page', 'invalid archive deletion request', 'invalid-data'));
    }
    const injected = this.failureFor('delete-event-month-archive-page');
    if (injected !== null) {
      return Err(injected);
    }
    const key = monthKey(lease.tenantId, lease.month);
    const state = this.archiveStates.get(key);
    if (
      state?.phase !== 'deleting' ||
      state.version !== lease.version ||
      state.leaseToken !== lease.leaseToken ||
      (state.leasedUntilMs ?? -1) < this.clock.nowMs()
    ) {
      return Err(failure('delete-event-month-archive-page', 'archive lease is stale or expired', 'conflict'));
    }
    const eventIds = this.eventMonthIndexes.get(key) ?? [];
    let budget = boundedLimit;
    let deletedEvents = 0;
    let deletedJobs = 0;
    while (budget > 0 && eventIds.length > 0) {
      const eventId = eventIds[0];
      if (eventId === undefined) {
        break;
      }
      const jobIds = this.eventJobs.get(eventId) ?? [];
      while (budget > 0 && jobIds.length > 0) {
        const jobId = jobIds.pop();
        if (jobId === undefined) {
          break;
        }
        const job = this.jobs.get(jobId);
        if (job !== undefined) {
          this.removePausedJobIndexes(job);
          this.removeDeadLetterEndpointIndex(job);
        }
        this.jobs.delete(jobId);
        this.deliveryLeases.delete(jobId);
        deletedJobs += 1;
        budget -= 1;
      }
      if (jobIds.length > 0 || budget === 0) {
        this.eventJobs.set(eventId, jobIds);
        break;
      }
      this.eventJobs.delete(eventId);
      this.events.delete(eventId);
      eventIds.shift();
      const retainedDeadLetters = (this.deadLetters.get(lease.tenantId) ?? []).filter(
        entry => entry.eventId !== eventId,
      );
      this.deadLetters.set(lease.tenantId, retainedDeadLetters);
      deletedEvents += 1;
      budget -= 1;
    }
    this.eventMonthIndexes.set(key, eventIds);
    return Ok({ deletedEvents, deletedJobs, done: eventIds.length === 0 });
  }

  async completeEventMonthArchive(lease: EventMonthArchiveLease): Promise<Result<void, StorageFailure>> {
    const key = monthKey(lease.tenantId, lease.month);
    const state = this.archiveStates.get(key);
    if (
      lease.phase !== 'deleting' ||
      state?.phase !== 'deleting' ||
      state.version !== lease.version ||
      state.leaseToken !== lease.leaseToken ||
      (this.eventMonthIndexes.get(key)?.length ?? 0) !== 0
    ) {
      return Err(failure('complete-event-month-archive', 'archive deletion is incomplete or stale', 'conflict'));
    }
    this.eventMonthIndexes.delete(key);
    this.archiveStates.delete(key);
    return Ok(undefined);
  }

  async abortEventMonthArchive(lease: EventMonthArchiveLease): Promise<Result<void, StorageFailure>> {
    const key = monthKey(lease.tenantId, lease.month);
    const state = this.archiveStates.get(key);
    if (
      lease.phase !== 'exporting' ||
      state?.phase !== 'exporting' ||
      state.version !== lease.version ||
      state.leaseToken !== lease.leaseToken
    ) {
      return Err(failure('abort-event-month-archive', 'archive lease is stale or already sealed', 'conflict'));
    }
    this.archiveStates.set(key, { phase: 'live', version: state.version });
    return Ok(undefined);
  }
}
