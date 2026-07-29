import type {
  Account,
  ConfigGeneration,
  CustomDomain,
  Endpoint,
  EndpointSigningCredential,
  LandscapeAcknowledgement,
  LandscapeEventSource,
  MeteringConfiguration,
  NativeCredential,
  ProviderCredential,
  Quota,
  ReplayAudit,
  Route,
  SubscriptionRegistration,
  Tenant,
  TenantConfiguration,
} from './types.ts';

export interface EndpointSigningCredentialRotation {
  id: string;
  accountId: string;
  tenantId: string;
  endpointId: string;
  expectedCurrentCredentialId?: string;
  secretPointer: string;
  rotatedAt: Date;
  overlapUntil: Date;
}

export interface ProviderCredentialRotation {
  id: string;
  accountId: string;
  tenantId: string;
  provider: string;
  secretPointer: string;
  rotatedAt: Date;
  overlapUntil: Date;
}

export interface ManagementRepository {
  health(): Promise<boolean>;

  getAccount(id: string): Promise<Account | undefined>;
  findAccountByName(name: string): Promise<Account | undefined>;
  listAccounts(): Promise<readonly Account[]>;
  saveAccount(account: Account): Promise<Account>;

  getTenant(id: string): Promise<Tenant | undefined>;
  findTenantByName(name: string): Promise<Tenant | undefined>;
  findTenantByIntakeSlug(slug: string): Promise<Tenant | undefined>;
  listTenants(accountId?: string): Promise<readonly Tenant[]>;
  saveTenant(tenant: Tenant): Promise<Tenant>;
  deleteTenant(id: string): Promise<boolean>;

  getQuota(tenantId: string): Promise<Quota | undefined>;
  saveQuota(quota: Quota): Promise<Quota>;
  getMeteringConfiguration(tenantId: string): Promise<MeteringConfiguration | undefined>;
  saveMeteringConfiguration(configuration: MeteringConfiguration): Promise<MeteringConfiguration>;

  getCredential(id: string): Promise<NativeCredential | undefined>;
  findCredentialByTokenHash(tokenHash: string): Promise<NativeCredential | undefined>;
  listCredentials(accountId: string): Promise<readonly NativeCredential[]>;
  saveCredential(credential: NativeCredential): Promise<NativeCredential>;
  consumeManagementRate(credentialId: string, windowSecond: number, cost: number, limit: number): Promise<boolean>;

  listProviderCredentials(tenantId: string): Promise<readonly ProviderCredential[]>;
  getProviderCredential(id: string): Promise<ProviderCredential | undefined>;
  saveProviderCredential(credential: ProviderCredential): Promise<ProviderCredential>;
  rotateProviderCredential(rotation: ProviderCredentialRotation): Promise<ProviderCredential>;

  getEndpointSigningCredential(id: string): Promise<EndpointSigningCredential | undefined>;
  listEndpointSigningCredentials(tenantId: string): Promise<readonly EndpointSigningCredential[]>;
  saveEndpointSigningCredential(credential: EndpointSigningCredential): Promise<EndpointSigningCredential>;
  rotateEndpointSigningCredential(rotation: EndpointSigningCredentialRotation): Promise<EndpointSigningCredential>;

  getCustomDomain(id: string): Promise<CustomDomain | undefined>;
  findCustomDomainByHostname(hostname: string): Promise<CustomDomain | undefined>;
  listCustomDomains(tenantId: string): Promise<readonly CustomDomain[]>;
  saveCustomDomain(domain: CustomDomain): Promise<CustomDomain>;
  deleteCustomDomain(id: string): Promise<boolean>;

  getRoute(id: string): Promise<Route | undefined>;
  findRouteByPath(tenantId: string, path: string): Promise<Route | undefined>;
  listRoutes(tenantId: string): Promise<readonly Route[]>;
  saveRoute(route: Route): Promise<Route>;
  deleteRoute(id: string): Promise<boolean>;

  getEndpoint(id: string): Promise<Endpoint | undefined>;
  listEndpoints(routeId: string): Promise<readonly Endpoint[]>;
  saveEndpoint(endpoint: Endpoint): Promise<Endpoint>;
  deleteEndpoint(id: string): Promise<boolean>;

  listSubscriptions(tenantId: string): Promise<readonly SubscriptionRegistration[]>;
  saveSubscription(subscription: SubscriptionRegistration): Promise<SubscriptionRegistration>;

  listLandscapeEventSources(accountId: string): Promise<readonly LandscapeEventSource[]>;
  saveLandscapeEventSource(source: LandscapeEventSource): Promise<LandscapeEventSource>;

  saveReplayAudit(audit: ReplayAudit): Promise<ReplayAudit>;
  listReplayAudits(tenantId: string): Promise<readonly ReplayAudit[]>;

  nextConfigGeneration(): Promise<number>;
  saveConfigGeneration(generation: ConfigGeneration): Promise<ConfigGeneration>;
  getConfigGeneration(generation: number): Promise<ConfigGeneration | undefined>;
  getActiveConfigGeneration(landscape: string): Promise<ConfigGeneration | undefined>;
  listConfigGenerations(landscape?: string): Promise<readonly ConfigGeneration[]>;
  saveLandscapeAcknowledgement(acknowledgement: LandscapeAcknowledgement): Promise<LandscapeAcknowledgement>;
  listLandscapeAcknowledgements(generation?: number): Promise<readonly LandscapeAcknowledgement[]>;

  listTenantConfigurations(): Promise<readonly TenantConfiguration[]>;
}
