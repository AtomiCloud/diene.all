export const DEFAULT_INTERNAL_ACCOUNT_NAME = 'internal/default' as const;
export const MAX_RETRY_WINDOW_SECONDS = 72 * 60 * 60;
export const DEFAULT_CONFIG_GRACE_SECONDS = 48 * 60 * 60;
export const MAX_ACCOUNTS = 1_000;
export const MAX_TENANTS_PER_ACCOUNT = 128;
export const MAX_ROUTES_PER_TENANT = 64;
export const MAX_ENDPOINTS_PER_ROUTE = 64;
export const MAX_FANOUT_PER_TENANT = 512;
export const MAX_CONFIG_DOCUMENT_BYTES = 4 * 1024 * 1024;
export const MAX_MANAGEMENT_REQUEST_BYTES = 1024 * 1024;
export const DOMAIN_CLAIM_TTL_SECONDS = 24 * 60 * 60;

export type AccountKind = 'internal' | 'external';
type AccountStatus = 'active' | 'suspended';
export type TenantSource = 'api' | 'cr';
type CredentialKind = 'management' | 'intake' | 'delivery_signing' | 'provider_verification';
type CredentialStatus = 'planned' | 'live' | 'overlap' | 'revoked';
type DomainStatus = 'pending' | 'verified' | 'active' | 'failed';
type CircuitState = 'closed' | 'open' | 'probing';
type GenerationStatus = 'writing' | 'activated' | 'active' | 'superseded' | 'failed';

export interface Account {
  id: string;
  name: string;
  kind: AccountKind;
  status: AccountStatus;
  createdAt: Date;
  updatedAt: Date;
}

export interface Tenant {
  id: string;
  accountId: string;
  name: string;
  intakeSlug: string;
  source: TenantSource;
  homeVlandscape: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface Quota {
  tenantId: string;
  intakeRps: number;
  burst: number;
  managementRps: number;
  retryWindowSeconds: number;
  dedupWindowSeconds: number;
  retentionMonths: number;
  updatedAt: Date;
}

export interface MeteringConfiguration {
  tenantId: string;
  enabled: boolean;
  exportIntervalSeconds: number;
  dimensions: readonly string[];
  billingAccountReference?: string;
  updatedAt: Date;
}

export interface NativeCredential {
  id: string;
  accountId: string;
  tenantId?: string;
  kind: CredentialKind;
  generation: number;
  tokenHash?: string;
  secretPointer?: string;
  scopes: readonly string[];
  status: CredentialStatus;
  liveFrom?: Date;
  lastConfirmedAt?: Date;
  overlapUntil?: Date;
  revokedAt?: Date;
  createdAt: Date;
}

export interface ProviderCredential {
  id: string;
  accountId: string;
  tenantId: string;
  provider: string;
  generation: number;
  secretPointer: string;
  status: CredentialStatus;
  lastConfirmedAt?: Date;
  overlapUntil?: Date;
  createdAt: Date;
}

export interface EndpointSigningCredential {
  id: string;
  accountId: string;
  tenantId: string;
  endpointId: string;
  generation: number;
  secretPointer: string;
  status: CredentialStatus;
  lastConfirmedAt?: Date;
  overlapUntil?: Date;
  createdAt: Date;
}

export interface CustomDomain {
  id: string;
  tenantId: string;
  hostname: string;
  registeredUrl: string;
  intakeTarget: string;
  challengeTarget: string;
  certificateSecretPointer: string;
  status: DomainStatus;
  verificationTokenHash: string;
  pendingUntil: Date;
  verifiedAt?: Date;
  activatedAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

interface CoordinateTarget {
  kind: 'coordinate';
  service: string;
  module: string;
  canonicalVlandscape: string;
}

interface UrlTarget {
  kind: 'url';
  url: string;
}

export type EndpointTarget = CoordinateTarget | UrlTarget;

export interface Route {
  id: string;
  tenantId: string;
  path: string;
  registeredUrl: string;
  provider: string;
  scheme?: string;
  providerCredentialId?: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface Endpoint {
  id: string;
  routeId: string;
  target: EndpointTarget;
  signingCredentialId: string;
  circuitState: CircuitState;
  circuitOpenedAt?: Date;
  lastProbeAt?: Date;
  lastProbeSucceededAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

export interface SubscriptionRegistration {
  id: string;
  tenantId: string;
  provider: string;
  externalId: string;
  retentionSeconds?: number;
  deadLetterTarget?: string;
  metadata: Readonly<Record<string, unknown>>;
  createdAt: Date;
  updatedAt: Date;
}

export interface LandscapeEventSource {
  accountId: string;
  landscape: string;
  queryUrl: string;
  replayUrl: string;
  credentialPointer: string;
  enabled: boolean;
  updatedAt: Date;
}

export type ReplayScope = { kind: 'event'; eventId: string } | { kind: 'endpoint'; endpointId: string };

export interface ReplayAudit {
  id: string;
  accountId: string;
  tenantId: string;
  landscape: string;
  scope: ReplayScope;
  reason: string;
  commandId: string;
  requestedAt: Date;
}

export interface ConfigGeneration {
  generation: number;
  landscape: string;
  status: GenerationStatus;
  contentHash: string;
  previousGeneration?: number;
  graceUntil?: Date;
  createdAt: Date;
  activatedAt?: Date;
}

export interface LandscapeAcknowledgement {
  landscape: string;
  generation: number;
  acknowledgedAt: Date;
  contentHash: string;
}

export interface ManagementHealth {
  repository: 'ok' | 'degraded';
  activeGenerations: readonly {
    landscape: string;
    generation: number;
    contentHash: string;
  }[];
  landscapes: readonly {
    landscape: string;
    generation?: number;
    current: boolean;
  }[];
}

export interface AuthenticatedPrincipal {
  accountId: string;
  tenantId?: string;
  credentialId: string;
  scopes: readonly string[];
}

export interface TenantConfiguration {
  tenant: Tenant;
  account: Account;
  quota: Quota;
  metering: MeteringConfiguration;
  domains: readonly CustomDomain[];
  providerCredentials: readonly ProviderCredential[];
  endpointSigningCredentials: readonly EndpointSigningCredential[];
  routes: readonly {
    route: Route;
    endpoints: readonly Endpoint[];
  }[];
}

export interface CompiledEndpoint {
  endpointId: string;
  address: string;
  addressKind: 'local' | 'canonical' | 'external';
  canonicalUrl: string;
  signingSecretPointer: string;
}

export interface CompiledRoute {
  routeId: string;
  path: string;
  registeredUrl: string;
  provider: string;
  scheme?: string;
  providerCredentialPointers: readonly string[];
  endpoints: readonly CompiledEndpoint[];
  orphanedUntilMs?: number;
}

export interface CompiledTenant {
  tenantId: string;
  name: string;
  intakeSlug: string;
  homeVlandscape: string;
  quota: Omit<Quota, 'tenantId' | 'updatedAt'>;
  metering: Omit<MeteringConfiguration, 'tenantId' | 'updatedAt'>;
  domains: readonly {
    hostname: string;
    registeredUrl: string;
  }[];
  providerCredentials: readonly {
    provider: string;
    generation: number;
    secretPointer: string;
    status: 'live' | 'overlap';
  }[];
  routes: readonly CompiledRoute[];
}

export interface LandscapeConfigDocument {
  generation: number;
  landscape: string;
  contentHash: string;
  tenants: readonly CompiledTenant[];
  createdAt: string;
}

export interface LandscapeTopology {
  landscapes: readonly string[];
  services: Readonly<
    Record<
      string,
      {
        module: string;
        localLandscapes: readonly string[];
        localAddressByLandscape?: Readonly<Record<string, string>>;
        canonicalVlandscape: string;
        canonicalAddress?: string;
      }
    >
  >;
}

export function coordinateKey(service: string, module: string): string {
  return `${service}/${module}`;
}
