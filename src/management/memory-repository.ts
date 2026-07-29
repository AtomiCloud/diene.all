import { ManagementError } from './errors.ts';
import type {
  EndpointSigningCredentialRotation,
  ManagementRepository,
  ProviderCredentialRotation,
} from './repository.ts';
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

function copy<T>(value: T): T {
  return structuredClone(value);
}

function sorted<T>(values: Iterable<T>, key: (value: T) => string | number): T[] {
  return [...values].sort((left, right) => {
    const leftKey = key(left);
    const rightKey = key(right);
    return leftKey < rightKey ? -1 : leftKey > rightKey ? 1 : 0;
  });
}

export type EndpointSigningCredentialRotationCheckpoint =
  | 'after-new-credential'
  | 'after-endpoint-rebind'
  | 'after-previous-overlap';

export class InMemoryManagementRepository implements ManagementRepository {
  readonly #accounts = new Map<string, Account>();
  readonly #tenants = new Map<string, Tenant>();
  readonly #quotas = new Map<string, Quota>();
  readonly #metering = new Map<string, MeteringConfiguration>();
  readonly #credentials = new Map<string, NativeCredential>();
  readonly #managementRateWindows = new Map<string, number>();
  readonly #providerCredentials = new Map<string, ProviderCredential>();
  readonly #endpointSigningCredentials = new Map<string, EndpointSigningCredential>();
  readonly #domains = new Map<string, CustomDomain>();
  readonly #routes = new Map<string, Route>();
  readonly #endpoints = new Map<string, Endpoint>();
  readonly #subscriptions = new Map<string, SubscriptionRegistration>();
  readonly #landscapeSources = new Map<string, LandscapeEventSource>();
  readonly #replayAudits = new Map<string, ReplayAudit>();
  readonly #generations = new Map<number, ConfigGeneration>();
  readonly #acknowledgements = new Map<string, LandscapeAcknowledgement>();

  protected endpointSigningCredentialRotationCheckpoint(
    _checkpoint: EndpointSigningCredentialRotationCheckpoint,
  ): void {}

  public async health(): Promise<boolean> {
    return true;
  }

  public async getAccount(id: string): Promise<Account | undefined> {
    return copy(this.#accounts.get(id));
  }

  public async findAccountByName(name: string): Promise<Account | undefined> {
    return copy([...this.#accounts.values()].find(item => item.name === name));
  }

  public async listAccounts(): Promise<readonly Account[]> {
    return copy(sorted(this.#accounts.values(), item => item.name));
  }

  public async saveAccount(account: Account): Promise<Account> {
    this.#accounts.set(account.id, copy(account));
    return copy(account);
  }

  public async getTenant(id: string): Promise<Tenant | undefined> {
    return copy(this.#tenants.get(id));
  }

  public async findTenantByName(name: string): Promise<Tenant | undefined> {
    return copy([...this.#tenants.values()].find(item => item.name === name));
  }

  public async findTenantByIntakeSlug(slug: string): Promise<Tenant | undefined> {
    return copy([...this.#tenants.values()].find(item => item.intakeSlug === slug));
  }

  public async listTenants(accountId?: string): Promise<readonly Tenant[]> {
    const values = [...this.#tenants.values()].filter(item => accountId === undefined || item.accountId === accountId);
    return copy(sorted(values, item => item.name));
  }

  public async saveTenant(tenant: Tenant): Promise<Tenant> {
    this.#tenants.set(tenant.id, copy(tenant));
    return copy(tenant);
  }

  public async deleteTenant(id: string): Promise<boolean> {
    const tenant = this.#tenants.get(id);
    if (tenant === undefined) return false;
    const hasDependencies =
      [...this.#credentials.values()].some(item => item.tenantId === id) ||
      [...this.#providerCredentials.values()].some(item => item.tenantId === id) ||
      [...this.#endpointSigningCredentials.values()].some(item => item.tenantId === id) ||
      [...this.#domains.values()].some(item => item.tenantId === id) ||
      [...this.#routes.values()].some(item => item.tenantId === id) ||
      [...this.#subscriptions.values()].some(item => item.tenantId === id) ||
      [...this.#replayAudits.values()].some(item => item.tenantId === id);
    if (hasDependencies) return false;
    this.#quotas.delete(id);
    this.#metering.delete(id);
    return this.#tenants.delete(id);
  }

  public async getQuota(tenantId: string): Promise<Quota | undefined> {
    return copy(this.#quotas.get(tenantId));
  }

  public async saveQuota(quota: Quota): Promise<Quota> {
    this.#quotas.set(quota.tenantId, copy(quota));
    return copy(quota);
  }

  public async getMeteringConfiguration(tenantId: string): Promise<MeteringConfiguration | undefined> {
    return copy(this.#metering.get(tenantId));
  }

  public async saveMeteringConfiguration(configuration: MeteringConfiguration): Promise<MeteringConfiguration> {
    this.#metering.set(configuration.tenantId, copy(configuration));
    return copy(configuration);
  }

  public async getCredential(id: string): Promise<NativeCredential | undefined> {
    return copy(this.#credentials.get(id));
  }

  public async findCredentialByTokenHash(tokenHash: string): Promise<NativeCredential | undefined> {
    return copy([...this.#credentials.values()].find(item => item.tokenHash === tokenHash));
  }

  public async listCredentials(accountId: string): Promise<readonly NativeCredential[]> {
    return copy(
      sorted(
        [...this.#credentials.values()].filter(item => item.accountId === accountId),
        item => `${item.kind}:${item.generation.toString().padStart(10, '0')}`,
      ),
    );
  }

  public async saveCredential(credential: NativeCredential): Promise<NativeCredential> {
    this.#credentials.set(credential.id, copy(credential));
    return copy(credential);
  }

  public async consumeManagementRate(
    credentialId: string,
    windowSecond: number,
    cost: number,
    limit: number,
  ): Promise<boolean> {
    const key = `${credentialId}:${windowSecond}`;
    const next = (this.#managementRateWindows.get(key) ?? 0) + cost;
    if (next > limit) return false;
    this.#managementRateWindows.set(key, next);
    return true;
  }

  public async listProviderCredentials(tenantId: string): Promise<readonly ProviderCredential[]> {
    return copy(
      sorted(
        [...this.#providerCredentials.values()].filter(item => item.tenantId === tenantId),
        item => `${item.provider}:${item.generation.toString().padStart(10, '0')}`,
      ),
    );
  }

  public async getProviderCredential(id: string): Promise<ProviderCredential | undefined> {
    return copy(this.#providerCredentials.get(id));
  }

  public async saveProviderCredential(credential: ProviderCredential): Promise<ProviderCredential> {
    this.#providerCredentials.set(credential.id, copy(credential));
    return copy(credential);
  }

  public async rotateProviderCredential(rotation: ProviderCredentialRotation): Promise<ProviderCredential> {
    const matching = [...this.#providerCredentials.values()].filter(
      credential => credential.tenantId === rotation.tenantId && credential.provider === rotation.provider,
    );
    for (const credential of matching) {
      if (credential.status === 'live') {
        this.#providerCredentials.set(credential.id, {
          ...credential,
          status: 'overlap',
          lastConfirmedAt: new Date(rotation.rotatedAt),
          overlapUntil: new Date(rotation.overlapUntil),
        });
      }
    }
    const credential: ProviderCredential = {
      id: rotation.id,
      accountId: rotation.accountId,
      tenantId: rotation.tenantId,
      provider: rotation.provider,
      generation: Math.max(0, ...matching.map(item => item.generation)) + 1,
      secretPointer: rotation.secretPointer,
      status: 'live',
      lastConfirmedAt: new Date(rotation.rotatedAt),
      createdAt: new Date(rotation.rotatedAt),
    };
    this.#providerCredentials.set(credential.id, copy(credential));
    return copy(credential);
  }

  public async getEndpointSigningCredential(id: string): Promise<EndpointSigningCredential | undefined> {
    return copy(this.#endpointSigningCredentials.get(id));
  }

  public async listEndpointSigningCredentials(tenantId: string): Promise<readonly EndpointSigningCredential[]> {
    return copy(
      sorted(
        [...this.#endpointSigningCredentials.values()].filter(item => item.tenantId === tenantId),
        item => `${item.endpointId}:${item.generation.toString().padStart(10, '0')}`,
      ),
    );
  }

  public async saveEndpointSigningCredential(
    credential: EndpointSigningCredential,
  ): Promise<EndpointSigningCredential> {
    this.#endpointSigningCredentials.set(credential.id, copy(credential));
    return copy(credential);
  }

  public async rotateEndpointSigningCredential(
    rotation: EndpointSigningCredentialRotation,
  ): Promise<EndpointSigningCredential> {
    if (this.#endpointSigningCredentials.has(rotation.id)) {
      throw new ManagementError('conflict', 'endpoint signing credential id already exists');
    }
    const endpoint = this.#endpoints.get(rotation.endpointId);
    if (
      (endpoint === undefined && rotation.expectedCurrentCredentialId !== undefined) ||
      (endpoint !== undefined && rotation.expectedCurrentCredentialId === undefined) ||
      (endpoint !== undefined && endpoint.signingCredentialId !== rotation.expectedCurrentCredentialId)
    ) {
      throw new ManagementError('conflict', 'endpoint signing credential changed during rotation');
    }
    if (endpoint !== undefined) {
      const route = this.#routes.get(endpoint.routeId);
      const current = this.#endpointSigningCredentials.get(endpoint.signingCredentialId);
      if (
        route === undefined ||
        route.tenantId !== rotation.tenantId ||
        current === undefined ||
        current.id !== rotation.expectedCurrentCredentialId ||
        current.accountId !== rotation.accountId ||
        current.tenantId !== rotation.tenantId ||
        current.endpointId !== rotation.endpointId ||
        current.status !== 'live'
      ) {
        throw new ManagementError('conflict', 'endpoint signing credential changed during rotation');
      }
    }
    const matching = [...this.#endpointSigningCredentials.values()].filter(
      credential => credential.tenantId === rotation.tenantId && credential.endpointId === rotation.endpointId,
    );
    const credential: EndpointSigningCredential = {
      id: rotation.id,
      accountId: rotation.accountId,
      tenantId: rotation.tenantId,
      endpointId: rotation.endpointId,
      generation: Math.max(0, ...matching.map(item => item.generation)) + 1,
      secretPointer: rotation.secretPointer,
      status: 'live',
      lastConfirmedAt: new Date(rotation.rotatedAt),
      createdAt: new Date(rotation.rotatedAt),
    };
    this.endpointSigningCredentialRotationCheckpoint('after-new-credential');
    const reboundEndpoint =
      endpoint === undefined
        ? undefined
        : {
            ...endpoint,
            signingCredentialId: credential.id,
            updatedAt: new Date(rotation.rotatedAt),
          };
    if (reboundEndpoint !== undefined) {
      this.endpointSigningCredentialRotationCheckpoint('after-endpoint-rebind');
    }
    const overlapped = matching
      .filter(item => item.status === 'live')
      .map(item => ({
        ...item,
        status: 'overlap' as const,
        lastConfirmedAt: new Date(rotation.rotatedAt),
        overlapUntil: new Date(rotation.overlapUntil),
      }));
    this.endpointSigningCredentialRotationCheckpoint('after-previous-overlap');
    for (const previous of overlapped) {
      this.#endpointSigningCredentials.set(previous.id, copy(previous));
    }
    this.#endpointSigningCredentials.set(credential.id, copy(credential));
    if (reboundEndpoint !== undefined) {
      this.#endpoints.set(reboundEndpoint.id, copy(reboundEndpoint));
    }
    return copy(credential);
  }

  public async getCustomDomain(id: string): Promise<CustomDomain | undefined> {
    return copy(this.#domains.get(id));
  }

  public async findCustomDomainByHostname(hostname: string): Promise<CustomDomain | undefined> {
    return copy([...this.#domains.values()].find(item => item.hostname === hostname));
  }

  public async listCustomDomains(tenantId: string): Promise<readonly CustomDomain[]> {
    return copy(
      sorted(
        [...this.#domains.values()].filter(item => item.tenantId === tenantId),
        item => item.hostname,
      ),
    );
  }

  public async saveCustomDomain(domain: CustomDomain): Promise<CustomDomain> {
    this.#domains.set(domain.id, copy(domain));
    return copy(domain);
  }

  public async deleteCustomDomain(id: string): Promise<boolean> {
    return this.#domains.delete(id);
  }

  public async getRoute(id: string): Promise<Route | undefined> {
    return copy(this.#routes.get(id));
  }

  public async findRouteByPath(tenantId: string, path: string): Promise<Route | undefined> {
    return copy([...this.#routes.values()].find(item => item.tenantId === tenantId && item.path === path));
  }

  public async listRoutes(tenantId: string): Promise<readonly Route[]> {
    return copy(
      sorted(
        [...this.#routes.values()].filter(item => item.tenantId === tenantId),
        item => item.path,
      ),
    );
  }

  public async saveRoute(route: Route): Promise<Route> {
    this.#routes.set(route.id, copy(route));
    return copy(route);
  }

  public async deleteRoute(id: string): Promise<boolean> {
    for (const endpoint of await this.listEndpoints(id)) {
      this.#endpoints.delete(endpoint.id);
    }
    return this.#routes.delete(id);
  }

  public async getEndpoint(id: string): Promise<Endpoint | undefined> {
    return copy(this.#endpoints.get(id));
  }

  public async listEndpoints(routeId: string): Promise<readonly Endpoint[]> {
    return copy(
      sorted(
        [...this.#endpoints.values()].filter(item => item.routeId === routeId),
        item => item.id,
      ),
    );
  }

  public async saveEndpoint(endpoint: Endpoint): Promise<Endpoint> {
    const route = this.#routes.get(endpoint.routeId);
    const credential = this.#endpointSigningCredentials.get(endpoint.signingCredentialId);
    if (
      route === undefined ||
      credential === undefined ||
      credential.tenantId !== route.tenantId ||
      credential.endpointId !== endpoint.id ||
      credential.status !== 'live'
    ) {
      throw new ManagementError('forbidden', 'endpoint signing credential ownership mismatch');
    }
    this.#endpoints.set(endpoint.id, copy(endpoint));
    return copy(endpoint);
  }

  public async deleteEndpoint(id: string): Promise<boolean> {
    return this.#endpoints.delete(id);
  }

  public async listSubscriptions(tenantId: string): Promise<readonly SubscriptionRegistration[]> {
    return copy(
      sorted(
        [...this.#subscriptions.values()].filter(item => item.tenantId === tenantId),
        item => `${item.provider}:${item.externalId}`,
      ),
    );
  }

  public async saveSubscription(subscription: SubscriptionRegistration): Promise<SubscriptionRegistration> {
    this.#subscriptions.set(subscription.id, copy(subscription));
    return copy(subscription);
  }

  public async listLandscapeEventSources(accountId: string): Promise<readonly LandscapeEventSource[]> {
    return copy(
      sorted(
        [...this.#landscapeSources.values()].filter(item => item.accountId === accountId),
        item => item.landscape,
      ),
    );
  }

  public async saveLandscapeEventSource(source: LandscapeEventSource): Promise<LandscapeEventSource> {
    this.#landscapeSources.set(`${source.accountId}:${source.landscape}`, copy(source));
    return copy(source);
  }

  public async saveReplayAudit(audit: ReplayAudit): Promise<ReplayAudit> {
    this.#replayAudits.set(audit.id, copy(audit));
    return copy(audit);
  }

  public async listReplayAudits(tenantId: string): Promise<readonly ReplayAudit[]> {
    return copy(
      sorted(
        [...this.#replayAudits.values()].filter(item => item.tenantId === tenantId),
        item => item.requestedAt.toISOString(),
      ),
    );
  }

  public async nextConfigGeneration(): Promise<number> {
    const current = Math.max(0, ...this.#generations.keys());
    return current + 1;
  }

  public async saveConfigGeneration(generation: ConfigGeneration): Promise<ConfigGeneration> {
    const existingGeneration = this.#generations.get(generation.generation);
    if (existingGeneration !== undefined && existingGeneration.landscape !== generation.landscape) {
      throw new ManagementError('conflict', 'configuration generation landscape is immutable', {
        generation: generation.generation,
        existingLandscape: existingGeneration.landscape,
        requestedLandscape: generation.landscape,
      });
    }
    if (generation.status === 'active') {
      for (const [key, existing] of this.#generations) {
        if (
          existing.landscape === generation.landscape &&
          existing.status === 'active' &&
          existing.generation !== generation.generation
        ) {
          this.#generations.set(key, {
            ...existing,
            status: 'superseded',
          });
        }
      }
    }
    this.#generations.set(generation.generation, copy(generation));
    return copy(generation);
  }

  public async getConfigGeneration(generation: number): Promise<ConfigGeneration | undefined> {
    return copy(this.#generations.get(generation));
  }

  public async getActiveConfigGeneration(landscape: string): Promise<ConfigGeneration | undefined> {
    const active = [...this.#generations.values()].filter(
      item => item.landscape === landscape && item.status === 'active',
    );
    return copy(sorted(active, item => item.generation).at(-1));
  }

  public async listConfigGenerations(landscape?: string): Promise<readonly ConfigGeneration[]> {
    return copy(
      sorted(
        [...this.#generations.values()].filter(item => landscape === undefined || item.landscape === landscape),
        item => item.generation,
      ),
    );
  }

  public async saveLandscapeAcknowledgement(
    acknowledgement: LandscapeAcknowledgement,
  ): Promise<LandscapeAcknowledgement> {
    this.#acknowledgements.set(`${acknowledgement.generation}:${acknowledgement.landscape}`, copy(acknowledgement));
    return copy(acknowledgement);
  }

  public async listLandscapeAcknowledgements(generation?: number): Promise<readonly LandscapeAcknowledgement[]> {
    return copy(
      sorted(
        [...this.#acknowledgements.values()].filter(item => generation === undefined || item.generation === generation),
        item => `${item.generation}:${item.landscape}`,
      ),
    );
  }

  public async listTenantConfigurations(): Promise<readonly TenantConfiguration[]> {
    const output: TenantConfiguration[] = [];
    for (const tenant of await this.listTenants()) {
      const account = await this.getAccount(tenant.accountId);
      const quota = await this.getQuota(tenant.id);
      const metering = await this.getMeteringConfiguration(tenant.id);
      if (account === undefined || quota === undefined || metering === undefined) {
        continue;
      }
      const routes = [];
      for (const route of await this.listRoutes(tenant.id)) {
        routes.push({
          route,
          endpoints: await this.listEndpoints(route.id),
        });
      }
      output.push({
        tenant,
        account,
        quota,
        metering,
        domains: await this.listCustomDomains(tenant.id),
        providerCredentials: await this.listProviderCredentials(tenant.id),
        endpointSigningCredentials: await this.listEndpointSigningCredentials(tenant.id),
        routes,
      });
    }
    return output;
  }
}
