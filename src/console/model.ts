type ConsoleAccountKind = 'default-internal' | 'internal' | 'external';

export type ConsoleCapability =
  | 'operations:read'
  | 'events:replay'
  | 'endpoints:replay'
  | 'endpoints:reenable'
  | 'retention:run';

export interface ConsoleIdentity {
  readonly accountId: string;
  readonly accountName: string;
  readonly accountKind: ConsoleAccountKind;
}

export interface ConsoleSessionRecord {
  readonly id: string;
  readonly revision: number;
  readonly tokenHash: string;
  readonly identity: ConsoleIdentity;
  readonly scope: ConsoleAuthorizationScope;
  readonly createdAt: Date;
  readonly lastSeenAt: Date;
  readonly idleExpiresAt: Date;
  readonly absoluteExpiresAt: Date;
  readonly rotateAt: Date;
}

export interface ConsoleSessionTicket {
  readonly token: string;
  readonly csrfToken: string;
  readonly requestCsrfToken: string;
  readonly sessionId: string;
  readonly identity: ConsoleIdentity;
  readonly scope: ConsoleAuthorizationScope;
  readonly expiresAt: Date;
  readonly rotated: boolean;
}

export type ConsoleSessionResolution =
  | { readonly kind: 'active'; readonly ticket: ConsoleSessionTicket }
  | { readonly kind: 'expired' }
  | { readonly kind: 'invalid' };

export interface ConsoleCredentials {
  readonly accountName: string;
  readonly bearerCredential: string;
}

export type ConsoleAuthenticationResult =
  | {
      readonly kind: 'authenticated';
      readonly identity: ConsoleIdentity;
      readonly scope: ConsoleAuthorizationScope;
    }
  | { readonly kind: 'rejected' }
  | { readonly kind: 'rate-limited'; readonly retryAfterSeconds: number };

export interface ConsoleAuthorizationScope {
  readonly tenants: '*' | readonly string[];
  readonly landscapes: '*' | readonly string[];
  readonly capabilities: readonly ConsoleCapability[];
}

export interface ConsoleNativeAuthorization {
  readonly scheme: 'Bearer';
  readonly token: string;
  readonly expiresAt: Date;
  readonly accountId: string;
  readonly sessionId: string;
  readonly scope: ConsoleAuthorizationScope;
}

export interface ConsoleAuthorizedPrincipal {
  readonly tokenId: string;
  readonly sessionId: string;
  readonly accountId: string;
  readonly issuedAt: Date;
  readonly expiresAt: Date;
  readonly scope: ConsoleAuthorizationScope;
}

type ConsoleFailureKind =
  | 'bad-request'
  | 'payload-too-large'
  | 'unauthenticated'
  | 'forbidden'
  | 'not-found'
  | 'conflict'
  | 'rate-limited'
  | 'unavailable'
  | 'unexpected';

export interface ConsoleFailure {
  readonly kind: ConsoleFailureKind;
  readonly title: string;
  readonly detail: string;
  readonly retryAfterSeconds?: number;
}

export type ConsoleResult<Value> =
  | { readonly ok: true; readonly value: Value }
  | { readonly ok: false; readonly error: ConsoleFailure };

export type ConsoleEventStatus =
  | 'all'
  | 'queued'
  | 'delivering'
  | 'retrying'
  | 'delivered'
  | 'dead-lettered'
  | 'withheld';

export interface ConsoleFilters {
  readonly landscape?: string;
  readonly tenant?: string;
  readonly provider?: string;
  readonly endpoint?: string;
  readonly status: ConsoleEventStatus;
}

export interface ConsoleFilterOption {
  readonly value: string;
  readonly label: string;
  readonly count?: number;
}

type ConsoleHealthState = 'healthy' | 'degraded' | 'critical' | 'paused' | 'unknown';

interface ConsoleIntakeHealth {
  readonly landscape: string;
  readonly state: ConsoleHealthState;
  readonly eventsPerMinute: number;
  readonly verificationFailureRate: number;
  readonly dedupHitRate: number;
  readonly lastAcceptedAt?: Date;
}

type ConsoleCircuitState = 'closed' | 'open' | 'half-open';

export interface ConsoleDeliveryHealth {
  readonly endpointId: string;
  readonly endpointName: string;
  readonly tenant: string;
  readonly provider: string;
  readonly landscape: string;
  readonly state: ConsoleHealthState;
  readonly circuit: ConsoleCircuitState;
  readonly successRate: number;
  readonly retryDepth: number;
  readonly lagSeconds: number;
  readonly deadLetterCount: number;
  readonly lastAttemptAt?: Date;
  readonly canReenable: boolean;
}

export interface ConsoleEventSummary {
  readonly id: string;
  readonly landscape: string;
  readonly tenant: string;
  readonly provider: string;
  readonly route: string;
  readonly endpointId: string;
  readonly endpointName: string;
  readonly status: Exclude<ConsoleEventStatus, 'all'>;
  readonly receivedAt: Date;
  readonly providerTimestamp?: Date;
  readonly providerSequence?: string;
  readonly attemptCount: number;
  readonly nextAttemptAt?: Date;
  readonly lagSeconds: number;
}

export interface ConsoleDeadLetter {
  readonly eventId: string;
  readonly landscape: string;
  readonly tenant: string;
  readonly provider: string;
  readonly endpointId: string;
  readonly endpointName: string;
  readonly exhaustedAt: Date;
  readonly finalStatus: number | 'network-error' | 'timeout';
  readonly attempts: number;
}

type ConsoleGenerationState = 'current' | 'compiling' | 'stale' | 'failed';

interface ConsoleConfigGeneration {
  readonly landscape: string;
  readonly desiredGeneration: number;
  readonly activeGeneration: number;
  readonly state: ConsoleGenerationState;
  readonly compiledAt?: Date;
  readonly detail?: string;
}

type ConsoleArchiveState = 'healthy' | 'delayed' | 'blocked';

interface ConsoleArchiveHealth {
  readonly landscape: string;
  readonly state: ConsoleArchiveState;
  readonly pendingStreams: number;
  readonly pendingBytes: number;
  readonly lastArchivedAt?: Date;
  readonly deletionBlocked: boolean;
  readonly detail?: string;
}

type ConsoleQuotaState = 'within-limit' | 'approaching' | 'exhausted';

interface ConsoleQuotaHealth {
  readonly tenant: string;
  readonly state: ConsoleQuotaState;
  readonly used: number;
  readonly limit: number;
  readonly window: string;
  readonly resetsAt: Date;
}

export interface ConsolePreviewVisibility {
  readonly state: 'visible' | 'withheld-d11';
  readonly detail: string;
  readonly affectedLandscapes: readonly string[];
}

type ConsoleRouteStateKind = 'active' | 'degraded' | 'orphaned-provider';

export interface ConsoleRouteState {
  readonly routeId: string;
  readonly route: string;
  readonly tenant: string;
  readonly provider: string;
  readonly landscape: string;
  readonly endpointCount: number;
  readonly state: ConsoleRouteStateKind;
  readonly activeGeneration: number;
  readonly detail?: string;
}

export interface ConsoleLandscapeFailure {
  readonly landscape: string;
  readonly operation: 'snapshot' | 'event' | 'endpoint' | 'action';
  readonly kind: ConsoleFailureKind;
  readonly detail: string;
}

export interface ConsoleLandscapeSource {
  readonly trustKind: 'account-owned';
  readonly accountId: string;
  readonly landscape: string;
  readonly queryUrl: string;
  readonly queryOrigin: string;
  readonly replayUrl: string;
  readonly replayOrigin: string;
  readonly enabled: boolean;
}

export interface ConsoleDashboardSnapshot {
  readonly generatedAt: Date;
  readonly filterOptions: {
    readonly landscapes: readonly ConsoleFilterOption[];
    readonly tenants: readonly ConsoleFilterOption[];
    readonly providers: readonly ConsoleFilterOption[];
    readonly endpoints: readonly ConsoleFilterOption[];
  };
  readonly intake: readonly ConsoleIntakeHealth[];
  readonly deliveries: readonly ConsoleDeliveryHealth[];
  readonly events: readonly ConsoleEventSummary[];
  readonly deadLetters: readonly ConsoleDeadLetter[];
  readonly routes: readonly ConsoleRouteState[];
  readonly generations: readonly ConsoleConfigGeneration[];
  readonly archives: readonly ConsoleArchiveHealth[];
  readonly quotas: readonly ConsoleQuotaHealth[];
  readonly previewVisibility: ConsolePreviewVisibility;
  readonly sourceFailures: readonly ConsoleLandscapeFailure[];
}

export interface ConsoleEventDetail extends ConsoleEventSummary {
  readonly allowedHeaders: Readonly<Record<string, string>>;
  readonly metadata: Readonly<Record<string, string>>;
  readonly payload: string;
  readonly payloadMediaType: string;
  readonly deliveryAddress: string;
  readonly lastResponseStatus?: number;
  readonly lastResponseBody?: string;
}

export interface ConsoleEndpointReplayTarget {
  readonly endpointId: string;
  readonly endpointName: string;
  readonly tenant: string;
  readonly provider: string;
  readonly landscape: string;
  readonly circuit: ConsoleCircuitState;
  readonly replayableEvents: number;
  readonly oldestEventAt?: Date;
}

export interface ConsoleActionReceipt {
  readonly actionId: string;
  readonly title: string;
  readonly detail: string;
  readonly acceptedAt: Date;
  readonly landscape: string;
  readonly affectedCount: number;
}

export interface ConsoleActionAudit {
  readonly requestId: string;
  readonly sessionId: string;
  readonly accountId: string;
  readonly reason: string;
}

interface ConsoleVerifiedActionAuthorization {
  readonly sessionId: string;
  readonly accountId: string;
  readonly expiresAt: Date;
  readonly scope: ConsoleAuthorizationScope;
}

export type ConsoleActionTarget =
  | {
      readonly kind: 'event-replay';
      readonly eventId: string;
      readonly endpointId?: string;
    }
  | { readonly kind: 'endpoint-replay'; readonly endpointId: string }
  | { readonly kind: 'circuit-reenable'; readonly endpointId: string };

export interface ConsoleActionAuditRequest {
  readonly authorization: ConsoleVerifiedActionAuthorization;
  readonly tenantId: string;
  readonly landscape: string;
  readonly target: ConsoleActionTarget;
  readonly context: ConsoleActionAudit;
}
