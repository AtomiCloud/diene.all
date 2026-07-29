/** Epoch milliseconds are used at boundaries so clocks remain injectable and deterministic. */
export type EpochMilliseconds = number;

/**
 * Product-sized maximum accepted HTTP request body, in bytes.
 *
 * Every legitimate provider webhook, Apple signed-notification backfill item,
 * Google RTDN envelope, and console form is comfortably within 1 MiB, while the
 * pod runs under a 512 MiB memory limit. This bound is enforced both by the Bun
 * server (`maxRequestBodySize`) and by the bounded intake stream reader so an
 * unauthenticated request is rejected with 413 before the body is materialized
 * or any route-independent work runs. It intentionally matches the
 * provider-operations response byte caps used elsewhere in the runtime.
 */
export const MERCURY_MAX_REQUEST_BODY_BYTES = 1_048_576;

export type HeaderMap = Readonly<Record<string, string>>;

type AddressKind = 'canonical' | 'external' | 'local';

interface EndpointRegistration {
  readonly id: string;
  readonly targetKind: 'coordinate' | 'external';
  readonly canonicalUrl: string;
  readonly localUrls: Readonly<Record<string, string>>;
  readonly signingSecretRef: string;
}

interface RouteRegistration {
  readonly id: string;
  /** Exact path registered with the provider, including its leading slash. */
  readonly path: string;
  readonly provider: string;
  readonly registeredUrl: string;
  readonly verificationSecretRef?: string;
  readonly endpoints: readonly EndpointRegistration[];
}

interface TenantRegistration {
  readonly id: string;
  /** URL-safe slug used only in the canonical `/t/:slug/...` path. */
  readonly slug: string;
  readonly registeredDomains: readonly string[];
  readonly intakeRps: number;
  readonly intakeBurst: number;
  readonly retryWindowMs: number;
  readonly routes: readonly RouteRegistration[];
}

export interface RegistrationSnapshot {
  readonly revision: string;
  readonly tenants: readonly TenantRegistration[];
}

export interface CompiledEndpoint {
  readonly id: string;
  readonly address: string;
  readonly addressKind: AddressKind;
  readonly canonicalUrl: string;
  readonly signingSecretRef: string;
}

export interface CompiledRoute {
  readonly id: string;
  readonly path: string;
  readonly canonicalPath: string;
  readonly provider: string;
  readonly registeredUrl: string;
  /** Ordered live-then-overlap verification credential references (dual-live rotation). */
  readonly verificationSecretRefs?: readonly string[];
  /** Backward-compatible newest single verification reference. */
  readonly verificationSecretRef?: string;
  readonly endpoints: readonly CompiledEndpoint[];
  readonly orphanedUntilMs?: EpochMilliseconds;
}

export interface CompiledTenant {
  readonly id: string;
  readonly slug: string;
  readonly registeredDomains: readonly string[];
  readonly intakeRps: number;
  readonly intakeBurst: number;
  readonly retryWindowMs: number;
  readonly routes: readonly CompiledRoute[];
}

export interface LandscapeRuntimeConfig {
  readonly generation: number;
  readonly landscape: string;
  readonly compiledAtMs: EpochMilliseconds;
  readonly sourceRevision: string;
  readonly tenants: readonly CompiledTenant[];
}

export interface ResolvedRoute {
  readonly tenant: CompiledTenant;
  readonly route: CompiledRoute;
  readonly orphaned: boolean;
}

export interface VerificationEvidence {
  readonly providerEventId?: string;
  readonly providerTimestampMs?: EpochMilliseconds;
  readonly providerSequence?: string;
  /** Stable provider signature material used only for fallback dedup derivation. */
  readonly signatureMaterial: string;
  readonly metadata: Readonly<Record<string, string>>;
}

export interface EndpointObligation {
  readonly id: string;
  readonly endpointId: string;
  readonly address: string;
  readonly addressKind: AddressKind;
  readonly signingSecretRef: string;
}

export interface WebhookEnvelope {
  readonly id: string;
  readonly tenantId: string;
  readonly routeId: string;
  readonly provider: string;
  readonly landingLandscape: string;
  readonly receivedAtMs: EpochMilliseconds;
  /** Set only after the HTTP adapter has constructed the provider 200 response. */
  readonly acknowledgedAtMs?: EpochMilliseconds;
  readonly providerTimestampMs?: EpochMilliseconds;
  readonly providerSequence?: string;
  readonly providerEventId?: string;
  readonly dedupId: string;
  readonly rawBody: Uint8Array;
  readonly headers: HeaderMap;
  readonly verificationMetadata: Readonly<Record<string, string>>;
  readonly obligations: readonly EndpointObligation[];
}

type DeliveryJobStatus = 'completed' | 'dead-letter' | 'paused' | 'pending';

export interface DeliveryAttempt {
  readonly number: number;
  readonly attemptedAtMs: EpochMilliseconds;
  readonly address: string;
  readonly signatureTimestampSeconds: number;
  readonly statusCode?: number;
  readonly transportError?: string;
  readonly replay: boolean;
}

export interface DeliveryJob {
  readonly id: string;
  readonly eventId: string;
  readonly tenantId: string;
  readonly routeId: string;
  readonly endpointId: string;
  readonly address: string;
  readonly addressKind: AddressKind;
  readonly signingSecretRef: string;
  readonly createdAtMs: EpochMilliseconds;
  readonly dueAtMs: EpochMilliseconds;
  readonly retryWindowMs: number;
  readonly status: DeliveryJobStatus;
  readonly attempts: readonly DeliveryAttempt[];
  readonly misrouteRefreshes: number;
  readonly replayCount: number;
}

export interface DeliveryClaimRequest {
  readonly claimToken: string;
  readonly leaseMs: number;
  readonly limit?: number;
  readonly nowMs: EpochMilliseconds;
}

export interface DeliveryJobClaim {
  readonly claimToken: string;
  readonly job: DeliveryJob;
  readonly leasedUntilMs: EpochMilliseconds;
}

export interface DeadLetterEntry {
  readonly landscape: string;
  readonly tenantId: string;
  readonly eventId: string;
  readonly endpointId: string;
  readonly jobId: string;
  readonly exhaustedAtMs: EpochMilliseconds;
  readonly reason: string;
}

export type RetainedEventStatus = 'completed' | 'dead-letter' | 'paused' | 'pending' | 'retrying';

export interface RetainedEventQuery {
  readonly tenantId: string;
  readonly provider?: string;
  readonly routeId?: string;
  readonly endpointId?: string;
  readonly status?: RetainedEventStatus;
  readonly receivedAfterMs?: EpochMilliseconds;
  readonly receivedBeforeMs?: EpochMilliseconds;
  readonly cursor?: string;
  readonly limit?: number;
}

export interface RetainedEventRecord {
  readonly envelope: WebhookEnvelope;
  readonly jobs: readonly DeliveryJob[];
  readonly status: RetainedEventStatus;
}

export interface RetainedEventPage {
  readonly items: readonly RetainedEventRecord[];
  readonly nextCursor?: string;
}

export type CircuitStatus = 'closed' | 'open';

export interface EndpointCircuit {
  readonly endpointKey: string;
  readonly status: CircuitStatus;
  readonly firstFailureAtMs?: EpochMilliseconds;
  readonly lastFailureAtMs?: EpochMilliseconds;
  readonly openedAtMs?: EpochMilliseconds;
}

export interface IntakeRequest {
  readonly path: string;
  /** The HTTP Host value is only an exact registered-domain lookup hint. */
  readonly host?: string;
  readonly headers: HeaderMap;
  readonly rawBody: Uint8Array;
}

export type IntakeOutcome =
  | Readonly<{ kind: 'accepted'; eventId: string }>
  | Readonly<{ kind: 'duplicate'; dedupId: string; eventId: string }>;

export interface ArchiveObject {
  readonly landscape: string;
  readonly tenantId: string;
  readonly month: string;
  readonly body: Uint8Array;
}

export interface ArchiveReceipt {
  readonly byteLength: number;
  readonly sha256: string;
  readonly storageTag?: string;
}

export interface TelemetryEvent {
  readonly name:
    | 'archive.failure'
    | 'archive.success'
    | 'circuit.closed'
    | 'circuit.opened'
    | 'config.materialize.failure'
    | 'config.retention.failure'
    | 'console.incident'
    | 'dedup.hit'
    | 'delivery.failure'
    | 'delivery.queue.depth'
    | 'delivery.retry'
    | 'delivery.success'
    | 'dlq.depth'
    | 'dlq.enqueued'
    | 'intake.accepted'
    | 'intake.unavailable'
    | 'intake.received'
    | 'orphaned-provider'
    | 'provider.apple.backfill'
    | 'quota.exhausted'
    | 'route.unknown'
    | 'runtime.job.failure'
    | 'runtime.shutdown.timeout'
    | 'stale-map'
    | 'verification.failure';
  readonly attributes: Readonly<Record<string, boolean | number | string>>;
  readonly value?: number;
}
