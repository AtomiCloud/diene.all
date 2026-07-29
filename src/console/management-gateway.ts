import { isManagementError } from '../management/errors.ts';
import type { ManagementService } from '../management/service.ts';
import type { AuthenticatedPrincipal, LandscapeEventSource } from '../management/types.ts';
import type {
  ConsoleAuthenticationResult,
  ConsoleAuthorizationScope,
  ConsoleCapability,
  ConsoleCredentials,
  ConsoleLandscapeSource,
  ConsoleNativeAuthorization,
  ConsoleResult,
} from './model.ts';
import type { ConsoleLoginRateLimiter, ConsoleManagementAccountGateway } from './ports.ts';

const MAX_NATIVE_BEARER_LENGTH = 512;

const hasManagementScope = (principal: AuthenticatedPrincipal, ...scopes: readonly string[]): boolean =>
  principal.scopes.includes('*') || scopes.some(scope => principal.scopes.includes(scope));

const consoleCapabilities = (principal: AuthenticatedPrincipal): readonly ConsoleCapability[] => {
  const capabilities: ConsoleCapability[] = [];
  if (hasManagementScope(principal, 'landscapes:read', 'operations:read', 'events:read')) {
    capabilities.push('operations:read');
  }
  if (hasManagementScope(principal, 'replay:write')) {
    capabilities.push('events:replay', 'endpoints:replay');
  }
  if (hasManagementScope(principal, 'circuits:write')) {
    capabilities.push('endpoints:reenable');
  }
  if (hasManagementScope(principal, 'retention:run')) {
    capabilities.push('retention:run');
  }
  return capabilities;
};

interface TrustedBaseUrl {
  readonly baseUrl: string;
  readonly origin: string;
}

const trustedBaseUrl = (value: string): TrustedBaseUrl | undefined => {
  try {
    const parsed = new URL(value);
    if (
      parsed.protocol === 'https:' &&
      parsed.username === '' &&
      parsed.password === '' &&
      parsed.port === '' &&
      parsed.hash === '' &&
      parsed.search === '' &&
      parsed.href === value
    ) {
      return { baseUrl: parsed.href, origin: parsed.origin };
    }
    return undefined;
  } catch {
    return undefined;
  }
};

const trustedSource = (source: LandscapeEventSource, accountId: string): ConsoleLandscapeSource | undefined => {
  if (source.accountId !== accountId) return undefined;
  const query = trustedBaseUrl(source.queryUrl);
  const replay = trustedBaseUrl(source.replayUrl);
  if (query === undefined || replay === undefined) return undefined;
  return {
    trustKind: 'account-owned',
    accountId,
    landscape: source.landscape,
    queryUrl: query.baseUrl,
    queryOrigin: query.origin,
    replayUrl: replay.baseUrl,
    replayOrigin: replay.origin,
    enabled: source.enabled,
  };
};

const enabledTrustedSources = (
  sources: readonly LandscapeEventSource[],
  accountId: string,
): readonly ConsoleLandscapeSource[] | undefined => {
  if (sources.some(source => source.accountId !== accountId)) return undefined;
  const trusted: ConsoleLandscapeSource[] = [];
  for (const source of sources) {
    if (!source.enabled) continue;
    const normalized = trustedSource(source, accountId);
    if (normalized === undefined) return undefined;
    trusted.push(normalized);
  }
  if (new Set(trusted.map(source => source.landscape)).size !== trusted.length) return undefined;
  return trusted.sort((left, right) => left.landscape.localeCompare(right.landscape));
};

export class MercuryManagementConsoleGateway implements ConsoleManagementAccountGateway {
  readonly #service: ManagementService;
  readonly #rateLimiter: ConsoleLoginRateLimiter;

  constructor(service: ManagementService, rateLimiter: ConsoleLoginRateLimiter) {
    this.#service = service;
    this.#rateLimiter = rateLimiter;
  }

  async authenticate(credentials: ConsoleCredentials): Promise<ConsoleAuthenticationResult> {
    const rate = await this.#rateLimiter.attempt(credentials.accountName);
    if (!rate.allowed) {
      return { kind: 'rate-limited', retryAfterSeconds: rate.retryAfterSeconds };
    }
    if (
      credentials.accountName.length === 0 ||
      credentials.accountName.length > 256 ||
      credentials.bearerCredential.length < 16 ||
      credentials.bearerCredential.length > MAX_NATIVE_BEARER_LENGTH ||
      /\s/.test(credentials.bearerCredential)
    ) {
      return { kind: 'rejected' };
    }
    try {
      const principal = await this.#service.authenticateBearer(`Bearer ${credentials.bearerCredential}`);
      const account = await this.#service.getAccountFor(principal, principal.accountId);
      if (account.name !== credentials.accountName) return { kind: 'rejected' };
      const capabilities = consoleCapabilities(principal);
      if (!capabilities.includes('operations:read')) return { kind: 'rejected' };
      const accountTenants = await this.#service.repository.listTenants(account.id);
      const tenants =
        principal.tenantId === undefined
          ? accountTenants
          : accountTenants.filter(tenant => tenant.id === principal.tenantId);
      if (principal.tenantId !== undefined && tenants.length !== 1) return { kind: 'rejected' };
      const sourceRecords = await this.#service.repository.listLandscapeEventSources(account.id);
      const sources = enabledTrustedSources(sourceRecords, account.id);
      if (sources === undefined) return { kind: 'rejected' };
      const scope: ConsoleAuthorizationScope = {
        tenants: tenants.map(tenant => tenant.id).sort(),
        landscapes: sources.map(source => source.landscape),
        capabilities,
      };
      await this.#rateLimiter.reset(credentials.accountName);
      return {
        kind: 'authenticated',
        identity: {
          accountId: account.id,
          accountName: account.name,
          accountKind: account.name === 'internal/default' ? 'default-internal' : account.kind,
        },
        scope,
      };
    } catch (error) {
      if (
        isManagementError(error) &&
        (error.code === 'unauthorized' || error.code === 'forbidden' || error.code === 'not_found')
      ) {
        return { kind: 'rejected' };
      }
      throw error;
    }
  }

  async landscapeSources(input: {
    readonly accountId: string;
    readonly authorization: ConsoleNativeAuthorization;
  }): Promise<ConsoleResult<readonly ConsoleLandscapeSource[]>> {
    if (input.accountId !== input.authorization.accountId) {
      return {
        ok: false,
        error: {
          kind: 'forbidden',
          title: 'Account scope rejected',
          detail: 'The native authorization does not cover this account.',
        },
      };
    }
    const allowedLandscapes = input.authorization.scope.landscapes;
    const records = await this.#service.repository.listLandscapeEventSources(input.accountId);
    const sources = enabledTrustedSources(records, input.accountId);
    if (sources === undefined) {
      return {
        ok: false,
        error: {
          kind: 'unavailable',
          title: 'Landscape source configuration rejected',
          detail: 'An enabled landscape operation source did not match its trusted account and HTTPS origin binding.',
        },
      };
    }
    return {
      ok: true,
      value: sources.filter(source => allowedLandscapes === '*' || allowedLandscapes.includes(source.landscape)),
    };
  }
}
