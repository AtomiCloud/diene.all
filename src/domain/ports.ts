import type { Result } from '@atomicloud/diene.result';
import type {
  ArchiveFailure,
  DeliveryFailure,
  SecretReadFailure,
  StorageFailure,
  TransportFailure,
  VerificationFailure,
} from './errors.ts';
import type {
  ArchiveObject,
  ArchiveReceipt,
  CircuitStatus,
  CompiledEndpoint,
  DeadLetterEntry,
  DeliveryAttempt,
  DeliveryClaimRequest,
  DeliveryJob,
  DeliveryJobClaim,
  EndpointCircuit,
  EpochMilliseconds,
  HeaderMap,
  LandscapeRuntimeConfig,
  RegistrationSnapshot,
  RetainedEventPage,
  RetainedEventQuery,
  TelemetryEvent,
  VerificationEvidence,
  WebhookEnvelope,
} from './models.ts';

export interface Clock {
  nowMs(): EpochMilliseconds;
}

export interface IdentifierFactory {
  create(): string;
}

export interface VerificationInput {
  readonly provider: string;
  readonly registeredUrl: string;
  /** Ordered live then overlap credential references; adapters may try each until one verifies. */
  readonly verificationSecretRefs?: readonly string[];
  /** Backward-compatible single credential reference. */
  readonly verificationSecretRef?: string;
  readonly headers: HeaderMap;
  readonly rawBody: Uint8Array;
}

export interface ProviderVerifierRegistry {
  verify(input: VerificationInput): Promise<Result<VerificationEvidence, VerificationFailure>>;
}

export interface ConfigSnapshotSource {
  read(): Promise<Result<RegistrationSnapshot, StorageFailure>>;
}

export interface RuntimeConfigReader {
  readActive(): Promise<Result<LandscapeRuntimeConfig | null, StorageFailure>>;
}

/** Write access is intentionally held only by MercuryConfigCompiler (Q-WH13). */
export interface RuntimeConfigStore extends RuntimeConfigReader {
  reserveGeneration(): Promise<Result<number, StorageFailure>>;
  stage(config: LandscapeRuntimeConfig): Promise<Result<void, StorageFailure>>;
  activate(
    generation: number,
    expectedPreviousGeneration: number | null,
    retainPreviousUntilMs?: EpochMilliseconds,
  ): Promise<Result<void, StorageFailure>>;
  retainGeneration(generation: number, untilMs: EpochMilliseconds): Promise<Result<void, StorageFailure>>;
  discardExpired(nowMs: EpochMilliseconds): Promise<Result<readonly number[], StorageFailure>>;
  discard(generation: number): Promise<Result<void, StorageFailure>>;
}

export interface QuotaRequest {
  readonly tenantId: string;
  readonly ratePerSecond: number;
  readonly burst: number;
  readonly nowMs: EpochMilliseconds;
}

export interface QuotaDecision {
  readonly allowed: boolean;
  readonly retryAfterSeconds: number;
}

export interface AtomicAcceptRequest {
  readonly dedupKey: string;
  readonly dedupTtlSeconds: number;
  readonly envelope: WebhookEnvelope;
  readonly jobs: readonly DeliveryJob[];
}

export type AtomicAcceptOutcome =
  | Readonly<{ kind: 'accepted'; eventId: string }>
  | Readonly<{ kind: 'duplicate'; eventId: string }>;

export interface DeadLetterPage {
  readonly items: readonly DeadLetterEntry[];
  readonly nextCursor?: string;
}

export interface BeginEventMonthArchiveRequest {
  readonly tenantId: string;
  readonly month: string;
  readonly leaseToken: string;
  readonly nowMs: EpochMilliseconds;
  readonly leaseMs: number;
}

export interface EventMonthArchiveManifest {
  readonly objectPath: string;
  readonly byteLength: number;
  readonly sha256: string;
  readonly partCount: number;
  readonly partsSha256: string;
  readonly eventCount: number;
  readonly jobCount: number;
  readonly deadLetterCount: number;
  readonly archiveByteLength: number;
}

export interface EventMonthArchiveLease {
  readonly tenantId: string;
  readonly month: string;
  readonly leaseToken: string;
  readonly version: number;
  readonly leasedUntilMs: EpochMilliseconds;
  readonly snapshotCursor: string;
  readonly phase: 'deleting' | 'exporting';
  readonly manifest?: EventMonthArchiveManifest;
}

export interface EventMonthArchivePage {
  readonly body: Uint8Array;
  readonly eventCount: number;
  readonly jobCount: number;
  readonly deadLetterCount: number;
  readonly firstCursor?: string;
  readonly lastCursor?: string;
  readonly nextCursor?: string;
}

export interface EventMonthDeletionPage {
  readonly deletedEvents: number;
  readonly deletedJobs: number;
  readonly done: boolean;
}

export interface FlowStore {
  readonly landscape: string;
  consumeQuota(request: QuotaRequest): Promise<Result<QuotaDecision, StorageFailure>>;
  acceptOnce(request: AtomicAcceptRequest): Promise<Result<AtomicAcceptOutcome, StorageFailure>>;
  acknowledgeEvent(eventId: string, acknowledgedAtMs: EpochMilliseconds): Promise<Result<void, StorageFailure>>;
  getEvent(eventId: string): Promise<Result<WebhookEnvelope | null, StorageFailure>>;
  getJob(jobId: string): Promise<Result<DeliveryJob | null, StorageFailure>>;
  listEventJobs(eventId: string): Promise<Result<readonly DeliveryJob[], StorageFailure>>;
  listRetainedEvents(query: RetainedEventQuery): Promise<Result<RetainedEventPage, StorageFailure>>;
  claimDueJobs(request: DeliveryClaimRequest): Promise<Result<readonly DeliveryJobClaim[], StorageFailure>>;
  claimJob(
    jobId: string,
    request: Omit<DeliveryClaimRequest, 'limit'>,
  ): Promise<Result<DeliveryJobClaim | null, StorageFailure>>;
  releaseJobClaim(jobId: string, claimToken: string): Promise<Result<void, StorageFailure>>;
  recordAttempt(
    jobId: string,
    attempt: DeliveryAttempt,
    claimToken?: string,
  ): Promise<Result<DeliveryJob, StorageFailure>>;
  completeJob(jobId: string, claimToken?: string): Promise<Result<DeliveryJob, StorageFailure>>;
  scheduleJob(
    jobId: string,
    dueAtMs: EpochMilliseconds,
    address?: string,
    misrouteRefreshes?: number,
    claimToken?: string,
    retainClaim?: boolean,
  ): Promise<Result<DeliveryJob, StorageFailure>>;
  pauseJob(jobId: string, claimToken?: string): Promise<Result<DeliveryJob, StorageFailure>>;
  expirePausedJobs(
    nowMs: EpochMilliseconds,
    limit?: number,
  ): Promise<Result<readonly DeadLetterEntry[], StorageFailure>>;
  resumeEndpoint(
    tenantId: string,
    endpointId: string,
    nowMs: EpochMilliseconds,
  ): Promise<Result<readonly DeliveryJob[], StorageFailure>>;
  deadLetter(
    jobId: string,
    exhaustedAtMs: EpochMilliseconds,
    reason: string,
    claimToken?: string,
  ): Promise<Result<DeadLetterEntry, StorageFailure>>;
  listDeadLetters(tenantId: string): Promise<Result<readonly DeadLetterEntry[], StorageFailure>>;
  /**
   * Returns an opaque-order, at-least-once cursor page. Consumers must tolerate
   * repeated entries and de-duplicate them by the complete returned entry tuple
   * (or a canonical serialization); no newest-first ordering is implied.
   */
  listDeadLetterPage(
    tenantId: string,
    cursor?: string,
    limit?: number,
  ): Promise<Result<DeadLetterPage, StorageFailure>>;
  replayEvent(eventId: string, nowMs: EpochMilliseconds): Promise<Result<readonly DeliveryJob[], StorageFailure>>;
  replayEndpoint(
    eventId: string,
    endpointId: string,
    nowMs: EpochMilliseconds,
  ): Promise<Result<DeliveryJob, StorageFailure>>;
  replayDeadLettersForEndpoint(
    tenantId: string,
    endpointId: string,
    nowMs: EpochMilliseconds,
  ): Promise<Result<readonly DeliveryJob[], StorageFailure>>;
  getCircuit(endpointKey: string): Promise<Result<EndpointCircuit, StorageFailure>>;
  recordEndpointFailure(
    endpointKey: string,
    nowMs: EpochMilliseconds,
    openAfterMs: number,
  ): Promise<Result<EndpointCircuit, StorageFailure>>;
  closeCircuit(endpointKey: string): Promise<Result<EndpointCircuit, StorageFailure>>;
  setCircuitStatus(
    endpointKey: string,
    status: CircuitStatus,
    nowMs: EpochMilliseconds,
  ): Promise<Result<EndpointCircuit, StorageFailure>>;
  listEventMonths(tenantId: string): Promise<Result<readonly string[], StorageFailure>>;
  beginEventMonthArchive(
    request: BeginEventMonthArchiveRequest,
  ): Promise<Result<EventMonthArchiveLease, StorageFailure>>;
  renewEventMonthArchive(
    lease: EventMonthArchiveLease,
    nowMs: EpochMilliseconds,
    leaseMs: number,
  ): Promise<Result<EventMonthArchiveLease, StorageFailure>>;
  readEventMonthArchivePage(
    lease: EventMonthArchiveLease,
    cursor: string | undefined,
    limit: number,
    maxBytes: number,
  ): Promise<Result<EventMonthArchivePage, StorageFailure>>;
  sealEventMonthArchive(
    lease: EventMonthArchiveLease,
    manifest: EventMonthArchiveManifest,
  ): Promise<Result<EventMonthArchiveLease, StorageFailure>>;
  deleteEventMonthArchivePage(
    lease: EventMonthArchiveLease,
    limit: number,
  ): Promise<Result<EventMonthDeletionPage, StorageFailure>>;
  completeEventMonthArchive(lease: EventMonthArchiveLease): Promise<Result<void, StorageFailure>>;
  abortEventMonthArchive(lease: EventMonthArchiveLease): Promise<Result<void, StorageFailure>>;
}

export interface SecretReader {
  read(secretRef: string): Promise<Result<Uint8Array, SecretReadFailure>>;
}

export interface DeliveryRequest {
  readonly url: string;
  readonly headers: HeaderMap;
  readonly body: Uint8Array;
  readonly signal?: AbortSignal;
}

export interface DeliveryResponse {
  readonly status: number;
  readonly headers: HeaderMap;
}

export interface DeliveryTransport {
  send(request: DeliveryRequest): Promise<Result<DeliveryResponse, TransportFailure>>;
}

export interface EndpointRefreshRequest {
  readonly tenantId: string;
  readonly routeId: string;
  readonly endpointId: string;
}

export interface EndpointRefresher {
  refreshEndpoint(request: EndpointRefreshRequest): Promise<Result<CompiledEndpoint, DeliveryFailure>>;
}

export interface ArchiveStore {
  put(object: ArchiveObject): Promise<Result<ArchiveReceipt, ArchiveFailure>>;
}

export interface RuntimeTelemetry {
  record(event: TelemetryEvent): Promise<void>;
}
