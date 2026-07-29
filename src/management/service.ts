import { lookup } from 'node:dns/promises';
import { createBearerToken, sha256 } from './crypto.ts';
import type { DomainOwnershipVerifier } from './domain-ownership.ts';
import { ManagementError } from './errors.ts';
import type { ManagementRepository } from './repository.ts';
import {
  type Account,
  type AccountKind,
  type AuthenticatedPrincipal,
  type CustomDomain,
  DEFAULT_INTERNAL_ACCOUNT_NAME,
  DOMAIN_CLAIM_TTL_SECONDS,
  type Endpoint,
  type EndpointSigningCredential,
  type EndpointTarget,
  type LandscapeEventSource,
  MAX_ACCOUNTS,
  MAX_ENDPOINTS_PER_ROUTE,
  MAX_FANOUT_PER_TENANT,
  MAX_RETRY_WINDOW_SECONDS,
  MAX_ROUTES_PER_TENANT,
  MAX_TENANTS_PER_ACCOUNT,
  type ManagementHealth,
  type MeteringConfiguration,
  type NativeCredential,
  type ProviderCredential,
  type Quota,
  type ReplayAudit,
  type ReplayScope,
  type Route,
  type SubscriptionRegistration,
  type Tenant,
  type TenantSource,
} from './types.ts';
import {
  assertSecretPointer,
  normalizeHostname,
  validateAccountName,
  validateEndpointTarget,
  validateIntakeSlug,
  validatePublicEndpointHostname,
  validateQuota,
  validateRegisteredUrl,
  validateResolvedEndpointAddresses,
  validateRoute,
  validateTenantName,
  validateVlandscape,
} from './validation.ts';

export interface ReplayDispatcher {
  dispatch(input: { landscape: string; tenantId: string; scope: ReplayScope; commandId: string }): Promise<void>;
}

export interface CircuitCommander {
  reenable(input: { landscape: string; tenantId: string; endpointId: string }): Promise<void>;
  probe(input: { landscape: string; tenantId: string; endpointId: string }): Promise<boolean>;
}

export interface EndpointDestinationResolver {
  resolve(hostname: string): Promise<readonly string[]>;
}

export interface ManagementServiceOptions {
  clock?: () => Date;
  idFactory?: () => string;
  tokenFactory?: () => string;
  replayDispatcher?: ReplayDispatcher;
  circuitCommander?: CircuitCommander;
  domainOwnershipVerifier?: DomainOwnershipVerifier;
  endpointDestinationResolver?: EndpointDestinationResolver;
}

export interface IssuedCredential {
  credential: NativeCredential;
  token: string;
}

export interface DomainClaimRegistration {
  domain: CustomDomain;
  records: readonly [{ type: 'CNAME'; name: string; target: string }, { type: 'CNAME'; name: string; target: string }];
}

const DEFAULT_QUOTA: Omit<Quota, 'tenantId' | 'updatedAt'> = {
  intakeRps: 50,
  burst: 200,
  managementRps: 20,
  retryWindowSeconds: MAX_RETRY_WINDOW_SECONDS,
  dedupWindowSeconds: MAX_RETRY_WINDOW_SECONDS,
  retentionMonths: 2,
};

function defaultIdFactory(): string {
  return crypto.randomUUID();
}

export class ManagementService {
  readonly #clock: () => Date;
  readonly #idFactory: () => string;
  readonly #tokenFactory: () => string;
  readonly #replayDispatcher?: ReplayDispatcher;
  readonly #circuitCommander?: CircuitCommander;
  readonly #domainOwnershipVerifier?: DomainOwnershipVerifier;
  readonly #endpointDestinationResolver: EndpointDestinationResolver;

  public constructor(
    public readonly repository: ManagementRepository,
    options: ManagementServiceOptions = {},
  ) {
    this.#clock = options.clock ?? (() => new Date());
    this.#idFactory = options.idFactory ?? defaultIdFactory;
    this.#tokenFactory = options.tokenFactory ?? createBearerToken;
    this.#replayDispatcher = options.replayDispatcher;
    this.#circuitCommander = options.circuitCommander;
    this.#domainOwnershipVerifier = options.domainOwnershipVerifier;
    this.#endpointDestinationResolver =
      options.endpointDestinationResolver ??
      ({
        resolve: async hostname => (await lookup(hostname, { all: true, verbatim: true })).map(item => item.address),
      } satisfies EndpointDestinationResolver);
  }

  public async authenticateBearer(authorization: string | undefined): Promise<AuthenticatedPrincipal> {
    const match = /^Bearer ([^\s]+)$/.exec(authorization ?? '');
    if (match?.[1] === undefined) {
      throw new ManagementError('unauthorized', 'a native Mercury bearer credential is required');
    }
    const credential = await this.repository.findCredentialByTokenHash(await sha256(match[1]));
    if (
      credential === undefined ||
      credential.kind !== 'management' ||
      (credential.status !== 'live' && credential.status !== 'overlap')
    ) {
      throw new ManagementError('unauthorized', 'invalid bearer credential');
    }
    const now = this.#clock();
    if (credential.status === 'overlap' && credential.overlapUntil !== undefined && credential.overlapUntil <= now) {
      throw new ManagementError('unauthorized', 'bearer credential expired');
    }
    const account = await this.repository.getAccount(credential.accountId);
    if (account === undefined || account.status !== 'active') {
      throw new ManagementError('unauthorized', 'account is not active');
    }
    return {
      accountId: credential.accountId,
      tenantId: credential.tenantId,
      credentialId: credential.id,
      scopes: credential.scopes,
    };
  }

  public requireScope(principal: AuthenticatedPrincipal, scope: string): void {
    if (!principal.scopes.includes('*') && !principal.scopes.includes(scope)) {
      throw new ManagementError('forbidden', `missing ${scope} scope`);
    }
  }

  public async consumeManagementRequest(principal: AuthenticatedPrincipal, cost = 1): Promise<void> {
    if (!Number.isSafeInteger(cost) || cost <= 0) {
      throw new ManagementError('invalid', 'management request cost must be a positive integer');
    }
    const quota = principal.tenantId === undefined ? undefined : await this.repository.getQuota(principal.tenantId);
    const limit = quota?.managementRps ?? DEFAULT_QUOTA.managementRps;
    const second = Math.floor(this.#clock().getTime() / 1000);
    if (!(await this.repository.consumeManagementRate(principal.credentialId, second, cost, limit))) {
      throw new ManagementError('rate_limited', 'management request rate exceeded', {
        limit,
        cost,
      });
    }
  }

  public async provisionDefaultInternalAccount(
    initialToken?: string,
  ): Promise<{ account: Account; issued?: IssuedCredential }> {
    const now = this.#clock();
    let account = await this.repository.findAccountByName(DEFAULT_INTERNAL_ACCOUNT_NAME);
    if (account === undefined) {
      account = await this.repository.saveAccount({
        id: this.#idFactory(),
        name: DEFAULT_INTERNAL_ACCOUNT_NAME,
        kind: 'internal',
        status: 'active',
        createdAt: now,
        updatedAt: now,
      });
    }
    const existing = (await this.repository.listCredentials(account.id)).find(
      item => item.kind === 'management' && (item.status === 'live' || item.status === 'overlap'),
    );
    if (existing !== undefined) {
      return { account };
    }
    const issued = await this.issueManagementCredential(account.id, undefined, ['*'], initialToken);
    return { account, issued };
  }

  public async createAccount(input: { name: string; kind: AccountKind }): Promise<Account> {
    validateAccountName(input.name, input.kind);
    const existing = await this.repository.findAccountByName(input.name);
    if (existing !== undefined) {
      if (existing.kind !== input.kind) {
        throw new ManagementError('conflict', 'account kind conflicts');
      }
      return existing;
    }
    if ((await this.repository.listAccounts()).length >= MAX_ACCOUNTS) {
      throw new ManagementError('conflict', 'account hard cap exceeded');
    }
    const now = this.#clock();
    return this.repository.saveAccount({
      id: this.#idFactory(),
      name: input.name,
      kind: input.kind,
      status: 'active',
      createdAt: now,
      updatedAt: now,
    });
  }

  public async getAccountFor(principal: AuthenticatedPrincipal, accountId: string): Promise<Account> {
    this.assertAccountAccess(principal, accountId);
    const account = await this.repository.getAccount(accountId);
    if (account === undefined) {
      throw new ManagementError('not_found', 'account not found');
    }
    return account;
  }

  public async createOrAdoptTenant(input: {
    accountId: string;
    name: string;
    intakeSlug: string;
    source: TenantSource;
    homeVlandscape: string;
    quota?: Omit<Quota, 'tenantId' | 'updatedAt'>;
  }): Promise<Tenant> {
    validateTenantName(input.name, input.source);
    validateIntakeSlug(input.intakeSlug);
    validateVlandscape(input.homeVlandscape);
    const account = await this.repository.getAccount(input.accountId);
    if (account === undefined) {
      throw new ManagementError('not_found', 'account not found');
    }
    if (
      (input.source === 'cr' && account.kind !== 'internal') ||
      (input.source === 'api' && account.kind !== 'external')
    ) {
      throw new ManagementError('invalid', 'tenant source and account partition do not match');
    }
    const existing = await this.repository.findTenantByName(input.name);
    if (existing !== undefined) {
      if (existing.homeVlandscape !== input.homeVlandscape || existing.intakeSlug !== input.intakeSlug) {
        throw new ManagementError(
          'immutable_home',
          'tenant home and intake slug are immutable; create a new tenant and cut over',
          {
            currentHome: existing.homeVlandscape,
            requestedHome: input.homeVlandscape,
            currentIntakeSlug: existing.intakeSlug,
            requestedIntakeSlug: input.intakeSlug,
          },
        );
      }
      if (existing.accountId !== input.accountId || existing.source !== input.source) {
        throw new ManagementError('conflict', 'tenant identity conflicts');
      }
      return existing;
    }
    const slugOwner = await this.repository.findTenantByIntakeSlug(input.intakeSlug);
    if (slugOwner !== undefined) {
      throw new ManagementError('conflict', 'intake slug is already in use');
    }
    if ((await this.repository.listTenants(input.accountId)).length >= MAX_TENANTS_PER_ACCOUNT) {
      throw new ManagementError('conflict', 'tenant hard cap exceeded');
    }
    const quota = input.quota ?? DEFAULT_QUOTA;
    validateQuota(quota);
    const now = this.#clock();
    const tenant = await this.repository.saveTenant({
      id: this.#idFactory(),
      accountId: input.accountId,
      name: input.name,
      intakeSlug: input.intakeSlug,
      source: input.source,
      homeVlandscape: input.homeVlandscape,
      createdAt: now,
      updatedAt: now,
    });
    await this.repository.saveQuota({
      tenantId: tenant.id,
      ...quota,
      updatedAt: now,
    });
    await this.repository.saveMeteringConfiguration({
      tenantId: tenant.id,
      enabled: true,
      exportIntervalSeconds: 60,
      dimensions: ['intake', 'delivery', 'replay', 'archive_bytes'],
      updatedAt: now,
    });
    return tenant;
  }

  public async assertTenantAccess(principal: AuthenticatedPrincipal, tenantId: string): Promise<Tenant> {
    const tenant = await this.repository.getTenant(tenantId);
    if (tenant === undefined) {
      throw new ManagementError('not_found', 'tenant not found');
    }
    this.assertAccountAccess(principal, tenant.accountId);
    if (principal.tenantId !== undefined && principal.tenantId !== tenant.id) {
      throw new ManagementError('forbidden', 'credential is tenant-scoped');
    }
    return tenant;
  }

  public async rejectIdentityChange(
    principal: AuthenticatedPrincipal,
    tenantId: string,
    requested: {
      homeVlandscape?: string;
      intakeSlug?: string;
    },
  ): Promise<Tenant> {
    const tenant = await this.assertTenantAccess(principal, tenantId);
    if (
      (requested.homeVlandscape !== undefined && tenant.homeVlandscape !== requested.homeVlandscape) ||
      (requested.intakeSlug !== undefined && tenant.intakeSlug !== requested.intakeSlug)
    ) {
      throw new ManagementError(
        'immutable_home',
        'tenant home and intake slug are immutable; create a new tenant and cut over',
      );
    }
    return tenant;
  }

  public async deleteTenant(principal: AuthenticatedPrincipal, tenantId: string): Promise<void> {
    this.requireScope(principal, 'tenants:write');
    const tenant = await this.assertTenantAccess(principal, tenantId);
    const dependencies = {
      routes: (await this.repository.listRoutes(tenant.id)).length,
      domains: (await this.repository.listCustomDomains(tenant.id)).length,
      subscriptions: (await this.repository.listSubscriptions(tenant.id)).length,
      providerCredentials: (await this.repository.listProviderCredentials(tenant.id)).length,
      endpointSigningCredentials: (await this.repository.listEndpointSigningCredentials(tenant.id)).length,
      nativeCredentials: (await this.repository.listCredentials(tenant.accountId)).filter(
        credential => credential.tenantId === tenant.id,
      ).length,
      replayAudits: (await this.repository.listReplayAudits(tenant.id)).length,
    };
    if (Object.values(dependencies).some(count => count > 0)) {
      throw new ManagementError('conflict', 'tenant still owns dependent resources', dependencies);
    }
    if (!(await this.repository.deleteTenant(tenant.id))) {
      throw new ManagementError('conflict', 'tenant deletion lost an empty-state race');
    }
  }

  public async setQuota(
    principal: AuthenticatedPrincipal,
    tenantId: string,
    input: Omit<Quota, 'tenantId' | 'updatedAt'>,
  ): Promise<Quota> {
    this.requireScope(principal, 'quotas:write');
    await this.assertTenantAccess(principal, tenantId);
    validateQuota(input);
    return this.repository.saveQuota({
      tenantId,
      ...input,
      updatedAt: this.#clock(),
    });
  }

  public async setMeteringConfiguration(
    principal: AuthenticatedPrincipal,
    tenantId: string,
    input: Omit<MeteringConfiguration, 'tenantId' | 'updatedAt'>,
  ): Promise<MeteringConfiguration> {
    this.requireScope(principal, 'metering:write');
    await this.assertTenantAccess(principal, tenantId);
    if (
      !Number.isSafeInteger(input.exportIntervalSeconds) ||
      input.exportIntervalSeconds <= 0 ||
      input.dimensions.length === 0 ||
      input.dimensions.some(dimension => !/^[a-z][a-z0-9_]{0,62}$/.test(dimension))
    ) {
      throw new ManagementError('invalid', 'invalid metering configuration');
    }
    return this.repository.saveMeteringConfiguration({
      tenantId,
      ...input,
      dimensions: [...new Set(input.dimensions)].sort(),
      updatedAt: this.#clock(),
    });
  }

  public async issueManagementCredential(
    accountId: string,
    tenantId: string | undefined,
    scopes: readonly string[],
    suppliedToken?: string,
  ): Promise<IssuedCredential> {
    const account = await this.repository.getAccount(accountId);
    if (account === undefined) {
      throw new ManagementError('not_found', 'account not found');
    }
    if (tenantId !== undefined) {
      const tenant = await this.repository.getTenant(tenantId);
      if (tenant === undefined || tenant.accountId !== accountId) {
        throw new ManagementError('invalid', 'tenant is not in account');
      }
    }
    const existing = (await this.repository.listCredentials(accountId)).filter(
      item => item.kind === 'management' && item.tenantId === tenantId,
    );
    const generation = Math.max(0, ...existing.map(item => item.generation)) + 1;
    const token = suppliedToken ?? this.#tokenFactory();
    const now = this.#clock();
    const credential = await this.repository.saveCredential({
      id: this.#idFactory(),
      accountId,
      tenantId,
      kind: 'management',
      generation,
      tokenHash: await sha256(token),
      scopes: [...scopes],
      status: 'live',
      liveFrom: now,
      lastConfirmedAt: now,
      createdAt: now,
    });
    return { credential, token };
  }

  public async rotateManagementCredential(
    principal: AuthenticatedPrincipal,
    accountId: string,
    input: {
      tenantId?: string;
      scopes?: readonly string[];
      overlapSeconds?: number;
    } = {},
  ): Promise<IssuedCredential> {
    this.requireScope(principal, 'credentials:rotate');
    this.assertAccountAccess(principal, accountId);
    if (principal.tenantId !== undefined && input.tenantId === undefined) {
      throw new ManagementError('forbidden', 'tenant-scoped credentials must name their exact tenant');
    }
    if (principal.tenantId !== undefined && input.tenantId !== principal.tenantId) {
      throw new ManagementError('forbidden', 'tenant-scoped credentials cannot rotate another tenant');
    }
    const overlapSeconds = input.overlapSeconds ?? 48 * 60 * 60;
    if (!Number.isSafeInteger(overlapSeconds) || overlapSeconds <= 0) {
      throw new ManagementError('invalid', 'overlapSeconds must be a positive integer');
    }
    const now = this.#clock();
    const overlapUntil = new Date(now.getTime() + overlapSeconds * 1000);
    const existing = (await this.repository.listCredentials(accountId)).filter(
      item => item.kind === 'management' && item.tenantId === input.tenantId && item.status === 'live',
    );
    const defaultScopes = existing.at(-1)?.scopes ?? principal.scopes;
    const requestedScopes = [...new Set(input.scopes ?? defaultScopes)];
    const globalIssuance = input.tenantId === undefined || requestedScopes.includes('*');
    if (
      globalIssuance &&
      (principal.tenantId !== undefined ||
        (!principal.scopes.includes('*') && !principal.scopes.includes('credentials:delegate')))
    ) {
      throw new ManagementError('forbidden', 'global credential issuance requires account-wide delegation');
    }
    if (!principal.scopes.includes('*') && requestedScopes.some(scope => !principal.scopes.includes(scope))) {
      throw new ManagementError('forbidden', 'requested credential scopes exceed caller scopes');
    }
    const issued = await this.issueManagementCredential(accountId, input.tenantId, requestedScopes);
    for (const credential of existing) {
      await this.repository.saveCredential({
        ...credential,
        status: 'overlap',
        lastConfirmedAt: now,
        overlapUntil,
      });
    }
    return issued;
  }

  public async registerProviderCredential(
    principal: AuthenticatedPrincipal,
    tenantId: string,
    input: { provider: string; secretPointer: string },
  ): Promise<ProviderCredential> {
    this.requireScope(principal, 'secrets:provision');
    if (principal.tenantId !== undefined) {
      throw new ManagementError('forbidden', 'tenant credentials cannot provision mounted-secret bindings');
    }
    const tenant = await this.assertTenantAccess(principal, tenantId);
    validateRoute('/credential', input.provider);
    assertSecretPointer(input.secretPointer);
    const now = this.#clock();
    return this.repository.rotateProviderCredential({
      id: this.#idFactory(),
      accountId: tenant.accountId,
      tenantId,
      provider: input.provider,
      secretPointer: input.secretPointer,
      rotatedAt: now,
      overlapUntil: new Date(now.getTime() + 48 * 60 * 60 * 1000),
    });
  }

  public async getProviderCredentialFor(
    principal: AuthenticatedPrincipal,
    tenantId: string,
    credentialId: string,
  ): Promise<ProviderCredential> {
    const tenant = await this.assertTenantAccess(principal, tenantId);
    const credential = await this.repository.getProviderCredential(credentialId);
    if (credential === undefined || credential.accountId !== tenant.accountId || credential.tenantId !== tenant.id) {
      throw new ManagementError('not_found', 'provider credential not found');
    }
    return credential;
  }

  public async registerEndpointSigningCredential(
    principal: AuthenticatedPrincipal,
    tenantId: string,
    input: { endpointId: string; secretPointer: string },
  ): Promise<EndpointSigningCredential> {
    this.requireScope(principal, 'secrets:provision');
    if (principal.tenantId !== undefined) {
      throw new ManagementError('forbidden', 'tenant credentials cannot provision mounted-secret bindings');
    }
    const tenant = await this.assertTenantAccess(principal, tenantId);
    assertSecretPointer(input.secretPointer);
    const endpoint = await this.repository.getEndpoint(input.endpointId);
    if (endpoint !== undefined) {
      const route = await this.repository.getRoute(endpoint.routeId);
      if (route === undefined || route.tenantId !== tenant.id) {
        throw new ManagementError('forbidden', 'endpoint belongs to another tenant');
      }
      const current = await this.repository.getEndpointSigningCredential(endpoint.signingCredentialId);
      if (
        current === undefined ||
        current.accountId !== tenant.accountId ||
        current.tenantId !== tenant.id ||
        current.endpointId !== endpoint.id ||
        current.status !== 'live'
      ) {
        throw new ManagementError('conflict', 'endpoint signing credential binding is not live and endpoint-owned');
      }
    }
    const now = this.#clock();
    return this.repository.rotateEndpointSigningCredential({
      id: this.#idFactory(),
      accountId: tenant.accountId,
      tenantId: tenant.id,
      endpointId: input.endpointId,
      expectedCurrentCredentialId: endpoint?.signingCredentialId,
      secretPointer: input.secretPointer,
      rotatedAt: now,
      overlapUntil: new Date(now.getTime() + 48 * 60 * 60 * 1000),
    });
  }

  public async registerCustomDomain(
    principal: AuthenticatedPrincipal,
    tenantId: string,
    input: { hostname: string },
  ): Promise<DomainClaimRegistration> {
    this.requireScope(principal, 'domains:write');
    const tenant = await this.assertTenantAccess(principal, tenantId);
    const hostname = normalizeHostname(input.hostname);
    let existing = await this.repository.findCustomDomainByHostname(hostname);
    const now = this.#clock();
    if (existing?.status === 'pending' && existing.pendingUntil <= now) {
      await this.repository.deleteCustomDomain(existing.id);
      existing = undefined;
    }
    if (existing !== undefined) {
      if (existing.tenantId !== tenantId) {
        throw new ManagementError('conflict', 'domain is already registered');
      }
      throw new ManagementError('conflict', 'domain claim already exists');
    }
    const domainId = this.#idFactory();
    const intakeTarget = `hooks.mercury.p.${tenant.homeVlandscape}.cluster.atomi.cloud`;
    const challengeTarget = `mercury-domain-${domainId}.domain-validation.${intakeTarget}`;
    const registeredUrl = `https://${hostname}`;
    const domain = await this.repository.saveCustomDomain({
      id: domainId,
      tenantId,
      hostname,
      registeredUrl,
      intakeTarget,
      challengeTarget,
      certificateSecretPointer: `/mercury-domain-${domainId}-tls`,
      status: 'pending',
      verificationTokenHash: await sha256(challengeTarget),
      pendingUntil: new Date(now.getTime() + DOMAIN_CLAIM_TTL_SECONDS * 1000),
      createdAt: now,
      updatedAt: now,
    });
    return {
      domain,
      records: [
        { type: 'CNAME', name: hostname, target: intakeTarget },
        { type: 'CNAME', name: `_acme-challenge.${hostname}`, target: challengeTarget },
      ],
    };
  }

  public async verifyCustomDomain(
    principal: AuthenticatedPrincipal,
    tenantId: string,
    domainId: string,
  ): Promise<CustomDomain> {
    this.requireScope(principal, 'domains:write');
    await this.assertTenantAccess(principal, tenantId);
    const domain = await this.repository.getCustomDomain(domainId);
    if (domain === undefined || domain.tenantId !== tenantId) {
      throw new ManagementError('not_found', 'custom domain not found');
    }
    const now = this.#clock();
    if (domain.status === 'pending' && domain.pendingUntil <= now) {
      await this.repository.deleteCustomDomain(domain.id);
      throw new ManagementError('not_found', 'custom domain claim expired');
    }
    if (this.#domainOwnershipVerifier === undefined) {
      throw new ManagementError('unavailable', 'custom domain ownership verifier is not configured');
    }
    const proof = await this.#domainOwnershipVerifier.verify({
      hostname: domain.hostname,
      intakeTarget: domain.intakeTarget,
      challengeTarget: domain.challengeTarget,
      certificateSecretPointer: domain.certificateSecretPointer,
      expectedTokenHash: domain.verificationTokenHash,
    });
    if (!proof.owned) {
      throw new ManagementError('conflict', 'custom domain ownership proof is not valid');
    }
    return this.repository.saveCustomDomain({
      ...domain,
      status: proof.certificateReady ? 'active' : 'verified',
      verifiedAt: domain.verifiedAt ?? now,
      activatedAt: proof.certificateReady ? (domain.activatedAt ?? now) : domain.activatedAt,
      updatedAt: now,
    });
  }

  public async deleteCustomDomain(
    principal: AuthenticatedPrincipal,
    tenantId: string,
    domainId: string,
  ): Promise<void> {
    this.requireScope(principal, 'domains:write');
    await this.assertTenantAccess(principal, tenantId);
    const domain = await this.repository.getCustomDomain(domainId);
    if (domain === undefined || domain.tenantId !== tenantId) {
      throw new ManagementError('not_found', 'custom domain not found');
    }
    for (const route of await this.repository.listRoutes(tenantId)) {
      let registeredHostname: string;
      try {
        registeredHostname = new URL(route.registeredUrl).hostname.toLowerCase().replace(/\.$/, '');
      } catch {
        throw new ManagementError('conflict', 'custom domain deletion is blocked by an invalid registered route URL');
      }
      if (registeredHostname === domain.hostname) {
        throw new ManagementError('conflict', 'custom domain is still used by a registered route');
      }
    }
    await this.repository.deleteCustomDomain(domainId);
  }

  public async upsertRoute(
    principal: AuthenticatedPrincipal,
    tenantId: string,
    input: {
      id?: string;
      path: string;
      registeredUrl: string;
      provider: string;
      scheme?: string;
      providerCredentialId?: string;
    },
  ): Promise<Route> {
    this.requireScope(principal, 'routes:write');
    await this.assertTenantAccess(principal, tenantId);
    validateRoute(input.path, input.provider, input.scheme);
    const tenant = await this.repository.getTenant(tenantId);
    if (tenant === undefined) {
      throw new ManagementError('not_found', 'tenant not found');
    }
    const domains = await this.repository.listCustomDomains(tenantId);
    validateRegisteredUrl({
      value: input.registeredUrl,
      routePath: input.path,
      intakeSlug: tenant.intakeSlug,
      homeVlandscape: tenant.homeVlandscape,
      customDomains: domains.filter(domain => domain.status === 'active').map(domain => domain.hostname),
    });
    const existing =
      (input.id === undefined ? undefined : await this.repository.getRoute(input.id)) ??
      (await this.repository.findRouteByPath(tenantId, input.path));
    if (existing !== undefined && existing.tenantId !== tenantId) {
      throw new ManagementError('conflict', 'route belongs to another tenant');
    }
    if (existing === undefined && (await this.repository.listRoutes(tenantId)).length >= MAX_ROUTES_PER_TENANT) {
      throw new ManagementError('conflict', 'route hard cap exceeded');
    }
    if (input.providerCredentialId !== undefined) {
      const credential = await this.repository.getProviderCredential(input.providerCredentialId);
      if (
        credential === undefined ||
        credential.accountId !== tenant.accountId ||
        credential.tenantId !== tenantId ||
        credential.provider !== input.provider ||
        (credential.status !== 'live' &&
          !(
            credential.status === 'overlap' &&
            credential.overlapUntil !== undefined &&
            credential.overlapUntil > this.#clock()
          ))
      ) {
        throw new ManagementError('forbidden', 'provider credential binding is not live and tenant-owned');
      }
    }
    const now = this.#clock();
    return this.repository.saveRoute({
      id: existing?.id ?? input.id ?? this.#idFactory(),
      tenantId,
      path: input.path,
      registeredUrl: input.registeredUrl,
      provider: input.provider,
      scheme: input.scheme,
      providerCredentialId: input.providerCredentialId,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    });
  }

  public async upsertEndpoint(
    principal: AuthenticatedPrincipal,
    tenantId: string,
    routeId: string,
    input: {
      id?: string;
      target: EndpointTarget;
      signingCredentialId: string;
    },
  ): Promise<Endpoint> {
    this.requireScope(principal, 'routes:write');
    const tenant = await this.assertTenantAccess(principal, tenantId);
    const route = await this.repository.getRoute(routeId);
    if (route === undefined || route.tenantId !== tenantId) {
      throw new ManagementError('not_found', 'route not found');
    }
    validateEndpointTarget(input.target, tenant.source);
    const existing = input.id === undefined ? undefined : await this.repository.getEndpoint(input.id);
    if (existing !== undefined && existing.routeId !== routeId) {
      throw new ManagementError('conflict', 'endpoint belongs to another route');
    }
    const endpointId = existing?.id ?? input.id ?? this.#idFactory();
    const signingCredential = await this.repository.getEndpointSigningCredential(input.signingCredentialId);
    if (
      signingCredential === undefined ||
      signingCredential.accountId !== tenant.accountId ||
      signingCredential.tenantId !== tenantId ||
      signingCredential.endpointId !== endpointId ||
      signingCredential.status !== 'live'
    ) {
      throw new ManagementError('forbidden', 'endpoint signing credential binding is not live and endpoint-owned');
    }
    if (input.target.kind === 'url') {
      const hostname = new URL(input.target.url).hostname;
      validatePublicEndpointHostname(hostname);
      let addresses: readonly string[];
      try {
        addresses = await this.#endpointDestinationResolver.resolve(hostname);
      } catch (error) {
        throw new ManagementError('invalid', 'external endpoint DNS could not be safely resolved', {
          cause: error instanceof Error ? error.message : String(error),
        });
      }
      validateResolvedEndpointAddresses(addresses);
    }
    const routeEndpoints = await this.repository.listEndpoints(routeId);
    if (existing === undefined && routeEndpoints.length >= MAX_ENDPOINTS_PER_ROUTE) {
      throw new ManagementError('conflict', 'endpoint hard cap exceeded');
    }
    if (existing === undefined) {
      let tenantFanout = 0;
      for (const tenantRoute of await this.repository.listRoutes(tenantId)) {
        tenantFanout += (await this.repository.listEndpoints(tenantRoute.id)).length;
      }
      if (tenantFanout >= MAX_FANOUT_PER_TENANT) {
        throw new ManagementError('conflict', 'tenant fan-out hard cap exceeded');
      }
      await this.consumeManagementRequest(principal, 1);
    }
    const now = this.#clock();
    return this.repository.saveEndpoint({
      id: endpointId,
      routeId,
      target: input.target,
      signingCredentialId: input.signingCredentialId,
      circuitState: existing?.circuitState ?? 'closed',
      circuitOpenedAt: existing?.circuitOpenedAt,
      lastProbeAt: existing?.lastProbeAt,
      lastProbeSucceededAt: existing?.lastProbeSucceededAt,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    });
  }

  public async deleteRoute(principal: AuthenticatedPrincipal, tenantId: string, routeId: string): Promise<void> {
    this.requireScope(principal, 'routes:write');
    await this.assertTenantAccess(principal, tenantId);
    const route = await this.repository.getRoute(routeId);
    if (route === undefined || route.tenantId !== tenantId) {
      throw new ManagementError('not_found', 'route not found');
    }
    await this.repository.deleteRoute(routeId);
  }

  public async deleteEndpoint(
    principal: AuthenticatedPrincipal,
    tenantId: string,
    routeId: string,
    endpointId: string,
  ): Promise<void> {
    this.requireScope(principal, 'routes:write');
    await this.assertTenantAccess(principal, tenantId);
    const route = await this.repository.getRoute(routeId);
    const endpoint = await this.repository.getEndpoint(endpointId);
    if (route === undefined || route.tenantId !== tenantId || endpoint === undefined || endpoint.routeId !== routeId) {
      throw new ManagementError('not_found', 'endpoint not found');
    }
    await this.repository.deleteEndpoint(endpointId);
  }

  public async registerSubscription(
    principal: AuthenticatedPrincipal,
    tenantId: string,
    input: {
      id?: string;
      provider: string;
      externalId: string;
      retentionSeconds?: number;
      deadLetterTarget?: string;
      metadata?: Readonly<Record<string, unknown>>;
    },
  ): Promise<SubscriptionRegistration> {
    this.requireScope(principal, 'subscriptions:write');
    await this.assertTenantAccess(principal, tenantId);
    validateRoute('/subscription', input.provider);
    if (
      input.retentionSeconds !== undefined &&
      (!Number.isSafeInteger(input.retentionSeconds) || input.retentionSeconds <= 0)
    ) {
      throw new ManagementError('invalid', 'retentionSeconds must be positive');
    }
    const existing = (await this.repository.listSubscriptions(tenantId)).find(
      item => item.provider === input.provider && item.externalId === input.externalId,
    );
    const now = this.#clock();
    return this.repository.saveSubscription({
      id: existing?.id ?? input.id ?? this.#idFactory(),
      tenantId,
      provider: input.provider,
      externalId: input.externalId,
      retentionSeconds: input.retentionSeconds,
      deadLetterTarget: input.deadLetterTarget,
      metadata: input.metadata ?? {},
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    });
  }

  public async saveLandscapeEventSource(
    principal: AuthenticatedPrincipal,
    input: Omit<LandscapeEventSource, 'accountId' | 'updatedAt'>,
  ): Promise<LandscapeEventSource> {
    this.requireScope(principal, 'landscapes:write');
    if (principal.tenantId !== undefined) {
      throw new ManagementError('forbidden', 'tenant credentials cannot mutate account landscape trust');
    }
    validateVlandscape(input.landscape);
    assertSecretPointer(input.credentialPointer);
    for (const value of [input.queryUrl, input.replayUrl]) {
      let parsed: URL;
      try {
        parsed = new URL(value);
      } catch {
        throw new ManagementError('invalid', 'landscape operation URL is invalid');
      }
      if (
        parsed.protocol !== 'https:' ||
        parsed.username !== '' ||
        parsed.password !== '' ||
        parsed.port !== '' ||
        parsed.search !== '' ||
        parsed.hash !== '' ||
        parsed.toString() !== value
      ) {
        throw new ManagementError('invalid', 'landscape operation URLs must be canonical HTTPS base URLs');
      }
    }
    return this.repository.saveLandscapeEventSource({
      ...input,
      accountId: principal.accountId,
      updatedAt: this.#clock(),
    });
  }

  public async requestReplay(
    principal: AuthenticatedPrincipal,
    input: {
      tenantId: string;
      landscape: string;
      scope: ReplayScope;
      reason: string;
    },
  ): Promise<ReplayAudit> {
    this.requireScope(principal, 'replay:write');
    await this.assertTenantAccess(principal, input.tenantId);
    if (this.#replayDispatcher === undefined) {
      throw new ManagementError('unavailable', 'replay dispatcher is not configured');
    }
    const source = (await this.repository.listLandscapeEventSources(principal.accountId)).find(
      item => item.landscape === input.landscape && item.enabled,
    );
    if (source === undefined) {
      throw new ManagementError('not_found', 'landscape event source not found');
    }
    if (input.scope.kind === 'endpoint') {
      const endpoint = await this.repository.getEndpoint(input.scope.endpointId);
      const route = endpoint === undefined ? undefined : await this.repository.getRoute(endpoint.routeId);
      if (route === undefined || route.tenantId !== input.tenantId) {
        throw new ManagementError('not_found', 'endpoint not found');
      }
    }
    const commandId = this.#idFactory();
    const audit = await this.repository.saveReplayAudit({
      id: this.#idFactory(),
      accountId: principal.accountId,
      tenantId: input.tenantId,
      landscape: input.landscape,
      scope: input.scope,
      reason: input.reason,
      commandId,
      requestedAt: this.#clock(),
    });
    try {
      await this.#replayDispatcher.dispatch({
        landscape: input.landscape,
        tenantId: input.tenantId,
        scope: input.scope,
        commandId,
      });
    } catch (error) {
      throw new ManagementError('unavailable', 'replay dispatcher failed', {
        commandId,
        cause: error instanceof Error ? error.message : String(error),
      });
    }
    return audit;
  }

  public async reenableCircuit(
    principal: AuthenticatedPrincipal,
    input: {
      tenantId: string;
      landscape: string;
      endpointId: string;
    },
  ): Promise<Endpoint> {
    this.requireScope(principal, 'circuits:write');
    await this.assertEndpointAccess(principal, input.tenantId, input.endpointId);
    if (this.#circuitCommander === undefined) {
      throw new ManagementError('unavailable', 'circuit commander is not configured');
    }
    try {
      await this.#circuitCommander.reenable(input);
    } catch (error) {
      throw new ManagementError('unavailable', 'circuit re-enable command failed', {
        cause: error instanceof Error ? error.message : String(error),
      });
    }
    const endpoint = await this.repository.getEndpoint(input.endpointId);
    if (endpoint === undefined) {
      throw new ManagementError('not_found', 'endpoint not found');
    }
    return this.repository.saveEndpoint({
      ...endpoint,
      circuitState: 'closed',
      circuitOpenedAt: undefined,
      updatedAt: this.#clock(),
    });
  }

  public async probeCircuit(
    principal: AuthenticatedPrincipal,
    input: {
      tenantId: string;
      landscape: string;
      endpointId: string;
    },
  ): Promise<{ endpoint: Endpoint; succeeded: boolean }> {
    this.requireScope(principal, 'circuits:write');
    await this.assertEndpointAccess(principal, input.tenantId, input.endpointId);
    if (this.#circuitCommander === undefined) {
      throw new ManagementError('unavailable', 'circuit commander is not configured');
    }
    let succeeded: boolean;
    try {
      succeeded = await this.#circuitCommander.probe(input);
    } catch (error) {
      throw new ManagementError('unavailable', 'circuit probe command failed', {
        cause: error instanceof Error ? error.message : String(error),
      });
    }
    const endpoint = await this.repository.getEndpoint(input.endpointId);
    if (endpoint === undefined) {
      throw new ManagementError('not_found', 'endpoint not found');
    }
    const now = this.#clock();
    const updated = await this.repository.saveEndpoint({
      ...endpoint,
      circuitState: succeeded ? 'closed' : 'open',
      circuitOpenedAt: succeeded ? undefined : (endpoint.circuitOpenedAt ?? now),
      lastProbeAt: now,
      lastProbeSucceededAt: succeeded ? now : endpoint.lastProbeSucceededAt,
      updatedAt: now,
    });
    return { endpoint: updated, succeeded };
  }

  public async health(): Promise<ManagementHealth> {
    const repositoryHealthy = await this.repository.health();
    const activeGenerations = (await this.repository.listConfigGenerations()).filter(
      generation => generation.status === 'active',
    );
    const acknowledgements = await this.repository.listLandscapeAcknowledgements();
    return {
      repository: repositoryHealthy ? 'ok' : 'degraded',
      activeGenerations: activeGenerations.map(generation => ({
        landscape: generation.landscape,
        generation: generation.generation,
        contentHash: generation.contentHash,
      })),
      landscapes: activeGenerations.map(active => {
        const acknowledgement = acknowledgements.find(
          item => item.landscape === active.landscape && item.generation === active.generation,
        );
        return {
          landscape: active.landscape,
          generation: acknowledgement?.generation,
          current:
            acknowledgement?.generation === active.generation && acknowledgement.contentHash === active.contentHash,
        };
      }),
    };
  }

  private assertAccountAccess(principal: AuthenticatedPrincipal, accountId: string): void {
    if (
      principal.accountId !== accountId &&
      !principal.scopes.includes('*') &&
      !principal.scopes.includes('accounts:all')
    ) {
      throw new ManagementError('forbidden', 'account access denied');
    }
  }

  private async assertEndpointAccess(
    principal: AuthenticatedPrincipal,
    tenantId: string,
    endpointId: string,
  ): Promise<void> {
    await this.assertTenantAccess(principal, tenantId);
    const endpoint = await this.repository.getEndpoint(endpointId);
    const route = endpoint === undefined ? undefined : await this.repository.getRoute(endpoint.routeId);
    if (route === undefined || route.tenantId !== tenantId) {
      throw new ManagementError('not_found', 'endpoint not found');
    }
  }
}
