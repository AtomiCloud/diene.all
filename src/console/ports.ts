import type {
  ConsoleActionAudit,
  ConsoleActionAuditRequest,
  ConsoleActionReceipt,
  ConsoleAuthenticationResult,
  ConsoleAuthorizationScope,
  ConsoleAuthorizedPrincipal,
  ConsoleCapability,
  ConsoleCredentials,
  ConsoleDashboardSnapshot,
  ConsoleEndpointReplayTarget,
  ConsoleEventDetail,
  ConsoleFilters,
  ConsoleIdentity,
  ConsoleLandscapeSource,
  ConsoleNativeAuthorization,
  ConsoleResult,
  ConsoleSessionRecord,
  ConsoleSessionResolution,
  ConsoleSessionTicket,
} from './model.ts';

export interface ConsoleClock {
  now(): Date;
}

export interface ConsoleSessionRepository {
  find(tokenHash: string): Promise<ConsoleSessionRecord | undefined>;
  /** Must reject a token-hash collision rather than replace an existing record. */
  create(record: ConsoleSessionRecord): Promise<boolean>;
  /** Atomically updates the record only when the same token hash is still live. */
  touch(current: ConsoleSessionRecord, replacement: ConsoleSessionRecord): Promise<boolean>;
  /** Atomically deletes the current record and creates its replacement. */
  rotate(currentTokenHash: string, replacement: ConsoleSessionRecord): Promise<boolean>;
  delete(tokenHash: string): Promise<void>;
}

export interface ConsoleSessionCryptography {
  randomToken(byteLength: number): string;
  hashToken(token: string): Promise<string>;
  deriveCsrfToken(token: string): Promise<string>;
}

export interface ConsoleSessions {
  create(identity: ConsoleIdentity, scope: ConsoleAuthorizationScope, now: Date): Promise<ConsoleSessionTicket>;
  resolve(token: string, now: Date): Promise<ConsoleSessionResolution>;
  revoke(token: string): Promise<void>;
}

export interface ConsoleManagementAccountGateway {
  authenticate(credentials: ConsoleCredentials): Promise<ConsoleAuthenticationResult>;
  landscapeSources(input: {
    readonly accountId: string;
    readonly authorization: ConsoleNativeAuthorization;
  }): Promise<ConsoleResult<readonly ConsoleLandscapeSource[]>>;
}

export interface ConsoleLoginRateLimiter {
  attempt(
    accountName: string,
  ): Promise<{ readonly allowed: true } | { readonly allowed: false; readonly retryAfterSeconds: number }>;
  reset(accountName: string): Promise<void>;
}

export interface ConsoleAuthorizationExchange {
  /**
   * Exchanges console identity server-side for a short-lived native bearer. Optional
   * capabilities are returned only when the account currently holds them.
   */
  exchange(request: {
    readonly sessionId: string;
    readonly identity: ConsoleIdentity;
    readonly scope: ConsoleAuthorizationScope;
    readonly requiredCapabilities: readonly ConsoleCapability[];
    readonly optionalCapabilities: readonly ConsoleCapability[];
  }): Promise<ConsoleResult<ConsoleNativeAuthorization>>;
}

export interface ConsoleNativeAuthorizer {
  authorize(
    authorization: string | undefined,
    requirement: {
      readonly landscape: string;
      readonly capability: ConsoleCapability;
      readonly tenant?: string;
      readonly accountId?: string;
    },
  ): Promise<ConsoleResult<ConsoleAuthorizedPrincipal>>;
}

export interface ConsoleActionAuditor {
  /** Resolve successfully only after the action context has been durably accepted. */
  accept(request: ConsoleActionAuditRequest): Promise<ConsoleResult<void>>;
}

export interface ConsoleOperations {
  dashboard(
    authorization: ConsoleNativeAuthorization,
    filters: ConsoleFilters,
  ): Promise<ConsoleResult<ConsoleDashboardSnapshot>>;

  event(
    authorization: ConsoleNativeAuthorization,
    landscape: string,
    eventId: string,
  ): Promise<ConsoleResult<ConsoleEventDetail>>;

  endpoint(
    authorization: ConsoleNativeAuthorization,
    landscape: string,
    endpointId: string,
  ): Promise<ConsoleResult<ConsoleEndpointReplayTarget>>;

  replayEvent(
    authorization: ConsoleNativeAuthorization,
    input: {
      readonly landscape: string;
      readonly eventId: string;
      readonly endpointId?: string;
      readonly audit: ConsoleActionAudit;
    },
  ): Promise<ConsoleResult<ConsoleActionReceipt>>;

  replayEndpoint(
    authorization: ConsoleNativeAuthorization,
    input: {
      readonly landscape: string;
      readonly endpointId: string;
      readonly audit: ConsoleActionAudit;
    },
  ): Promise<ConsoleResult<ConsoleActionReceipt>>;

  reenableEndpoint(
    authorization: ConsoleNativeAuthorization,
    input: {
      readonly landscape: string;
      readonly endpointId: string;
      readonly audit: ConsoleActionAudit;
    },
  ): Promise<ConsoleResult<ConsoleActionReceipt>>;
}

export interface ConsoleRequestSecurity {
  issueToken(byteLength: number): string;
  equal(left: string, right: string): boolean;
}

export interface ConsoleIncidentReporter {
  report(input: {
    readonly requestId: string;
    readonly method: string;
    readonly path: string;
    readonly error: unknown;
  }): Promise<void>;
}
