export type LandscapeOperationsCapability =
  | 'operations:read'
  | 'events:replay'
  | 'endpoints:replay'
  | 'endpoints:reenable'
  | 'retention:run';

export interface LandscapeHealthDto {
  readonly landscape: string;
  readonly status: 'degraded' | 'healthy';
  readonly checkedAtMs: number;
  readonly activeGeneration: number | null;
  readonly compiledAtMs?: number;
  readonly sourceRevision?: string;
  readonly supervisor: 'running' | 'stopped' | 'unknown';
}

type LandscapeRetainedEventStatus = 'completed' | 'dead-letter' | 'paused' | 'pending' | 'retrying';

export interface LandscapeEventSummaryDto {
  readonly id: string;
  readonly tenantId: string;
  readonly routeId: string;
  readonly provider: string;
  readonly landscape: string;
  readonly receivedAtMs: number;
  readonly providerEventId?: string;
  readonly providerTimestampMs?: number;
  readonly providerSequence?: string;
  readonly status: LandscapeRetainedEventStatus;
  readonly endpointIds: readonly string[];
  readonly attemptCount: number;
  readonly nextDueAtMs?: number;
}

export interface LandscapeEventListDto {
  readonly landscape: string;
  readonly tenantId: string;
  readonly items: readonly LandscapeEventSummaryDto[];
  readonly nextCursor?: string;
}

interface LandscapeDeliveryAttemptDto {
  readonly number: number;
  readonly attemptedAtMs: number;
  readonly address: string;
  readonly statusCode?: number;
  readonly transportError?: string;
  readonly replay: boolean;
}

export interface LandscapeDeliveryJobDto {
  readonly id: string;
  readonly eventId: string;
  readonly endpointId: string;
  readonly address: string;
  readonly addressKind: 'canonical' | 'external' | 'local';
  readonly createdAtMs: number;
  readonly dueAtMs: number;
  readonly retryWindowMs: number;
  readonly status: 'completed' | 'dead-letter' | 'paused' | 'pending';
  readonly attempts: readonly LandscapeDeliveryAttemptDto[];
  readonly misrouteRefreshes: number;
  readonly replayCount: number;
}

export interface LandscapeEventDetailDto {
  readonly event: LandscapeEventSummaryDto;
  readonly headers: Readonly<Record<string, string>>;
  readonly verificationMetadata: Readonly<Record<string, string>>;
  readonly rawBodyBase64: string;
  readonly jobs: readonly LandscapeDeliveryJobDto[];
}

export interface LandscapeDeadLetterDto {
  readonly landscape: string;
  readonly tenantId: string;
  readonly eventId: string;
  readonly endpointId: string;
  readonly jobId: string;
  readonly provider?: string;
  readonly exhaustedAtMs: number;
  readonly reason: string;
  readonly attemptCount: number;
  readonly finalOutcome?: number | string;
}

export interface LandscapeDeadLetterListDto {
  readonly landscape: string;
  readonly tenantId: string;
  readonly items: readonly LandscapeDeadLetterDto[];
}

export interface LandscapeActionAuditDto {
  readonly requestId: string;
  readonly sessionId: string;
  readonly accountId: string;
  readonly reason: string;
}

export interface LandscapeActionReceiptDto {
  readonly actionId: string;
  readonly action: 'circuit-reenabled' | 'endpoint-replayed' | 'event-replayed';
  readonly landscape: string;
  readonly tenantId: string;
  readonly acceptedAtMs: number;
  readonly affectedCount: number;
}

export interface LandscapeRetentionReceiptDto {
  readonly actionId: string;
  readonly action: 'retention-run';
  readonly landscape: string;
  readonly tenantId: string;
  readonly completedAtMs: number;
  readonly archivedMonths: readonly string[];
  readonly liveMonths: readonly string[];
}

export interface LandscapeProblemDto {
  readonly type: string;
  readonly title: string;
  readonly status: number;
  readonly code: string;
  readonly detail: string;
}
