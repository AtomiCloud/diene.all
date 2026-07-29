import { sha256, stableJson } from './crypto.ts';
import { ManagementError } from './errors.ts';
import type { ManagementRepository } from './repository.ts';
import {
  type CompiledEndpoint,
  type CompiledRoute,
  type CompiledTenant,
  type ConfigGeneration,
  coordinateKey,
  DEFAULT_CONFIG_GRACE_SECONDS,
  type LandscapeConfigDocument,
  type LandscapeTopology,
  MAX_CONFIG_DOCUMENT_BYTES,
  MAX_ENDPOINTS_PER_ROUTE,
  MAX_FANOUT_PER_TENANT,
  MAX_RETRY_WINDOW_SECONDS,
  MAX_ROUTES_PER_TENANT,
  type TenantConfiguration,
} from './types.ts';
import { assertSecretPointer, validateEndpointTarget, validateQuota, validateRoute } from './validation.ts';

export interface LandscapeConfigWriter {
  readActiveConfiguration(landscape: string): Promise<ActiveLandscapeConfiguration | undefined>;
  writeCompleteGeneration(document: LandscapeConfigDocument): Promise<void>;
  flipGeneration(
    landscape: string,
    generation: number,
    contentHash: string,
  ): Promise<{ activated: boolean; acknowledged: boolean }>;
  retainPreviousGeneration(landscape: string, generation: number, until: Date): Promise<void>;
}

export interface CompilerOptions {
  clock?: () => Date;
  graceSeconds?: number;
  preActivate?: (document: LandscapeConfigDocument) => Promise<void>;
}

export interface ActiveLandscapeConfiguration {
  generation: number;
  landscape: string;
  contentHash: string;
  tenants: readonly {
    tenantId: string;
    routes: readonly CompiledRoute[];
  }[];
}

export interface CompilationResult {
  generation: ConfigGeneration;
  documents: readonly LandscapeConfigDocument[];
  acknowledgedLandscapes: readonly string[];
}

function addressWithPath(base: string, provider: string): string {
  return `${base.replace(/\/+$/, '')}/internal/webhooks/${provider}`;
}

function sortedConfigurations(configurations: readonly TenantConfiguration[]): TenantConfiguration[] {
  return [...configurations]
    .sort((left, right) => left.tenant.name.localeCompare(right.tenant.name))
    .map(configuration => ({
      ...configuration,
      domains: [...configuration.domains].sort((left, right) => left.hostname.localeCompare(right.hostname)),
      providerCredentials: [...configuration.providerCredentials].sort(
        (left, right) => left.provider.localeCompare(right.provider) || left.generation - right.generation,
      ),
      endpointSigningCredentials: [...configuration.endpointSigningCredentials].sort(
        (left, right) => left.endpointId.localeCompare(right.endpointId) || left.generation - right.generation,
      ),
      routes: [...configuration.routes]
        .sort((left, right) => left.route.path.localeCompare(right.route.path))
        .map(registration => ({
          route: registration.route,
          endpoints: [...registration.endpoints].sort((left, right) => left.id.localeCompare(right.id)),
        })),
    }));
}

export class MercuryConfigurationCompiler {
  readonly #clock: () => Date;
  readonly #graceSeconds: number;
  readonly #preActivate?: (document: LandscapeConfigDocument) => Promise<void>;

  public constructor(
    private readonly repository: ManagementRepository,
    private readonly writer: LandscapeConfigWriter,
    options: CompilerOptions = {},
  ) {
    this.#clock = options.clock ?? (() => new Date());
    this.#graceSeconds = options.graceSeconds ?? DEFAULT_CONFIG_GRACE_SECONDS;
    this.#preActivate = options.preActivate;
  }

  public async compileAndPublish(topology: LandscapeTopology): Promise<CompilationResult> {
    this.validateTopology(topology);
    const landscape = topology.landscapes[0];
    if (landscape === undefined) {
      throw new ManagementError('invalid', 'compiler topology must contain one local landscape');
    }
    const activeConfiguration = await this.writer.readActiveConfiguration(landscape);
    await this.reconcileActivatedRuntime(landscape, activeConfiguration);
    const configurations = sortedConfigurations(await this.repository.listTenantConfigurations());
    this.validateRegistrations(configurations);

    const generationNumber = await this.repository.nextConfigGeneration();
    const previous = await this.repository.getActiveConfigGeneration(landscape);
    const createdAt = this.#clock();
    const compiledByLandscape = [
      {
        landscape,
        tenants: configurations.map(configuration =>
          this.compileTenant(
            configuration,
            topology,
            landscape,
            activeConfiguration?.tenants.find(candidate => candidate.tenantId === configuration.tenant.id)?.routes,
            createdAt.getTime(),
          ),
        ),
      },
    ];
    const serialized = stableJson(compiledByLandscape);
    const documentBytes = new TextEncoder().encode(serialized).byteLength;
    if (documentBytes > MAX_CONFIG_DOCUMENT_BYTES) {
      throw new ManagementError('invalid', 'compiled configuration exceeds the document byte hard cap', {
        documentBytes,
        limit: MAX_CONFIG_DOCUMENT_BYTES,
      });
    }
    const contentHash = await sha256(serialized);
    const writing: ConfigGeneration = {
      generation: generationNumber,
      landscape,
      status: 'writing',
      contentHash,
      previousGeneration: previous?.generation,
      createdAt,
    };
    await this.repository.saveConfigGeneration(writing);
    const documents: LandscapeConfigDocument[] = compiledByLandscape.map(compiled => ({
      generation: generationNumber,
      landscape: compiled.landscape,
      contentHash,
      tenants: compiled.tenants,
      createdAt: createdAt.toISOString(),
    }));

    let runtimeActivated = false;
    try {
      const document = documents[0];
      if (document === undefined) {
        throw new ManagementError('compiler_failed', 'local landscape document is absent');
      }
      await this.writer.writeCompleteGeneration(document);
      await this.#preActivate?.(document);
      const result = await this.writer.flipGeneration(document.landscape, generationNumber, contentHash);
      runtimeActivated = result.activated;
      if (!result.activated) {
        throw new ManagementError('compiler_failed', 'runtime generation was not activated');
      }
      const activated: ConfigGeneration = {
        ...writing,
        status: 'activated',
        activatedAt: this.#clock(),
      };
      await this.repository.saveConfigGeneration(activated);
      if (!result.acknowledged) {
        throw new ManagementError('compiler_failed', 'runtime generation activated without matching read-back');
      }
      await this.repository.saveLandscapeAcknowledgement({
        landscape: document.landscape,
        generation: generationNumber,
        acknowledgedAt: this.#clock(),
        contentHash,
      });
      const graceUntil =
        previous === undefined ? undefined : new Date(this.#clock().getTime() + this.#graceSeconds * 1000);
      if (previous !== undefined && graceUntil !== undefined) {
        await this.writer.retainPreviousGeneration(landscape, previous.generation, graceUntil);
        await this.repository.saveConfigGeneration({
          ...previous,
          status: 'superseded',
          graceUntil,
        });
      }
      const active: ConfigGeneration = {
        ...activated,
        status: 'active',
        graceUntil,
      };
      await this.repository.saveConfigGeneration(active);
      return {
        generation: active,
        documents,
        acknowledgedLandscapes: [landscape],
      };
    } catch (error) {
      try {
        await this.repository.saveConfigGeneration({
          ...writing,
          status: runtimeActivated ? 'activated' : 'failed',
          activatedAt: runtimeActivated ? this.#clock() : undefined,
        });
      } catch {
        // The runtime read-back journal repairs a writing row on the next pass.
      }
      throw new ManagementError('compiler_failed', 'configuration generation could not be published', {
        generation: generationNumber,
        landscape,
        cause: error instanceof Error ? error.message : String(error),
      });
    }
  }

  private compileTenant(
    configuration: TenantConfiguration,
    topology: LandscapeTopology,
    landscape: string,
    previousRoutes: readonly CompiledRoute[] | undefined,
    nowMs: number,
  ): CompiledTenant {
    const {
      tenant,
      quota: { tenantId: _tenantId, updatedAt: _updatedAt, ...quota },
      metering: { tenantId: _meteringTenantId, updatedAt: _meteringUpdatedAt, ...metering },
    } = configuration;
    const usableProviderCredentials = configuration.providerCredentials
      .filter(
        credential =>
          credential.accountId === configuration.account.id &&
          credential.tenantId === tenant.id &&
          (credential.status === 'live' ||
            (credential.status === 'overlap' &&
              credential.overlapUntil !== undefined &&
              credential.overlapUntil.getTime() > nowMs)),
      )
      .sort(
        (left, right) =>
          left.provider.localeCompare(right.provider) ||
          Number(left.status !== 'live') - Number(right.status !== 'live') ||
          right.generation - left.generation,
      );
    const routes: CompiledRoute[] = configuration.routes.map(({ route, endpoints }) => {
      const selected =
        route.providerCredentialId === undefined
          ? undefined
          : configuration.providerCredentials.find(credential => credential.id === route.providerCredentialId);
      if (
        route.providerCredentialId !== undefined &&
        (selected === undefined ||
          selected.accountId !== configuration.account.id ||
          selected.tenantId !== tenant.id ||
          selected.provider !== route.provider)
      ) {
        throw new ManagementError('forbidden', 'compiled provider credential is not tenant-owned');
      }
      const providerCredentialPointers =
        selected === undefined
          ? []
          : usableProviderCredentials
              .filter(credential => credential.provider === route.provider)
              .map(credential => credential.secretPointer);
      return {
        routeId: route.id,
        path: route.path,
        registeredUrl: route.registeredUrl,
        provider: route.provider,
        scheme: route.scheme,
        providerCredentialPointers,
        endpoints: endpoints.map(endpoint => {
          const signingCredential = configuration.endpointSigningCredentials.find(
            credential => credential.id === endpoint.signingCredentialId,
          );
          if (
            signingCredential === undefined ||
            signingCredential.accountId !== configuration.account.id ||
            signingCredential.tenantId !== tenant.id ||
            signingCredential.endpointId !== endpoint.id ||
            signingCredential.status !== 'live'
          ) {
            throw new ManagementError('forbidden', 'compiled endpoint signing credential is not live and owned');
          }
          return this.compileEndpoint(endpoint, route.provider, topology, landscape, signingCredential.secretPointer);
        }),
      };
    });
    const routeIds = new Set(routes.map(route => route.routeId));
    const providers = new Set(routes.map(route => route.provider));
    const orphaned = (previousRoutes ?? [])
      .filter(route => !routeIds.has(route.routeId) && !providers.has(route.provider))
      .map(route => ({
        ...route,
        endpoints: [],
        orphanedUntilMs: route.orphanedUntilMs ?? nowMs + MAX_RETRY_WINDOW_SECONDS * 1000,
      }))
      .filter(route => (route.orphanedUntilMs ?? 0) > nowMs);
    return {
      tenantId: tenant.id,
      name: tenant.name,
      intakeSlug: tenant.intakeSlug,
      homeVlandscape: tenant.homeVlandscape,
      quota,
      metering,
      domains: configuration.domains
        .filter(domain => domain.status === 'active')
        .map(domain => ({
          hostname: domain.hostname,
          registeredUrl: domain.registeredUrl,
        })),
      providerCredentials: usableProviderCredentials.map(credential => ({
        provider: credential.provider,
        generation: credential.generation,
        secretPointer: credential.secretPointer,
        status: credential.status as 'live' | 'overlap',
      })),
      routes: [...routes, ...orphaned],
    };
  }

  private compileEndpoint(
    endpoint: TenantConfiguration['routes'][number]['endpoints'][number],
    provider: string,
    topology: LandscapeTopology,
    landscape: string,
    signingSecretPointer: string,
  ): CompiledEndpoint {
    if (endpoint.target.kind === 'url') {
      return {
        endpointId: endpoint.id,
        address: endpoint.target.url,
        addressKind: 'external',
        canonicalUrl: endpoint.target.url,
        signingSecretPointer,
      };
    }
    const key = coordinateKey(endpoint.target.service, endpoint.target.module);
    const service = topology.services[key];
    if (service === undefined) {
      throw new ManagementError('invalid', `coordinate ${key} is not served by the supplied topology`);
    }
    if (service.module !== endpoint.target.module) {
      throw new ManagementError('invalid', `coordinate ${key} does not match topology module`);
    }
    const local = service.localLandscapes.includes(landscape);
    const canonicalBase =
      service.canonicalAddress ??
      `https://${endpoint.target.module}.${endpoint.target.service}.mercury.${service.canonicalVlandscape}.cluster.atomi.cloud`;
    const canonicalUrl = addressWithPath(canonicalBase, provider);
    if (local) {
      const base =
        service.localAddressByLandscape?.[landscape] ??
        `http://${endpoint.target.module}.${endpoint.target.service}.svc.cluster.local`;
      return {
        endpointId: endpoint.id,
        address: addressWithPath(base, provider),
        addressKind: 'local',
        canonicalUrl,
        signingSecretPointer,
      };
    }
    return {
      endpointId: endpoint.id,
      address: canonicalUrl,
      addressKind: 'canonical',
      canonicalUrl,
      signingSecretPointer,
    };
  }

  private async reconcileActivatedRuntime(
    landscape: string,
    runtime: ActiveLandscapeConfiguration | undefined,
  ): Promise<void> {
    if (runtime === undefined) return;
    if (runtime.landscape !== landscape) {
      throw new ManagementError('compiler_failed', 'active runtime landscape does not match compiler ownership');
    }
    const recordedActive = await this.repository.getActiveConfigGeneration(landscape);
    if (recordedActive?.generation === runtime.generation) {
      if (recordedActive.contentHash !== runtime.contentHash) {
        throw new ManagementError('compiler_failed', 'active runtime hash conflicts with Neon generation ledger');
      }
      return;
    }
    const activated = await this.repository.getConfigGeneration(runtime.generation);
    if (activated === undefined || activated.landscape !== landscape || activated.contentHash !== runtime.contentHash) {
      throw new ManagementError('compiler_failed', 'active runtime generation is absent from the Neon journal');
    }
    await this.repository.saveLandscapeAcknowledgement({
      landscape,
      generation: activated.generation,
      acknowledgedAt: this.#clock(),
      contentHash: activated.contentHash,
    });
    const previous =
      activated.previousGeneration === undefined
        ? undefined
        : await this.repository.getConfigGeneration(activated.previousGeneration);
    const graceUntil =
      previous === undefined ? undefined : new Date(this.#clock().getTime() + this.#graceSeconds * 1000);
    if (previous !== undefined && previous.landscape === landscape && graceUntil !== undefined) {
      await this.writer.retainPreviousGeneration(landscape, previous.generation, graceUntil);
      await this.repository.saveConfigGeneration({
        ...previous,
        status: 'superseded',
        graceUntil,
      });
    }
    await this.repository.saveConfigGeneration({
      ...activated,
      status: 'active',
      graceUntil,
      activatedAt: activated.activatedAt ?? this.#clock(),
    });
  }

  private validateTopology(topology: LandscapeTopology): void {
    if (topology.landscapes.length !== 1) {
      throw new ManagementError('invalid', 'compiler topology must contain exactly one local landscape');
    }
    for (const [key, service] of Object.entries(topology.services)) {
      if (
        !key.endsWith(`/${service.module}`) ||
        service.localLandscapes.some(landscape => !topology.landscapes.includes(landscape))
      ) {
        throw new ManagementError('invalid', `invalid topology entry ${key}`);
      }
    }
  }

  private validateRegistrations(configurations: readonly TenantConfiguration[]): void {
    const now = this.#clock();
    for (const configuration of configurations) {
      const {
        quota: { tenantId: _tenantId, updatedAt: _updatedAt, ...quota },
      } = configuration;
      validateQuota(quota);
      if (configuration.routes.length > MAX_ROUTES_PER_TENANT) {
        throw new ManagementError('invalid', 'tenant route hard cap exceeded during compilation');
      }
      const fanout = configuration.routes.reduce((total, registration) => total + registration.endpoints.length, 0);
      if (fanout > MAX_FANOUT_PER_TENANT) {
        throw new ManagementError('invalid', 'tenant fan-out hard cap exceeded during compilation');
      }
      for (const domain of configuration.domains) {
        if (domain.status === 'active') {
          assertSecretPointer(domain.certificateSecretPointer);
        }
      }
      const paths = new Set<string>();
      const schemesByProvider = new Map<string, string>();
      for (const { route, endpoints } of configuration.routes) {
        validateRoute(route.path, route.provider, route.scheme);
        if (endpoints.length > MAX_ENDPOINTS_PER_ROUTE) {
          throw new ManagementError('invalid', 'route endpoint hard cap exceeded during compilation');
        }
        if (paths.has(route.path)) {
          throw new ManagementError('conflict', `duplicate route path ${route.path}`);
        }
        paths.add(route.path);
        if (route.scheme !== undefined) {
          const existing = schemesByProvider.get(route.provider);
          if (existing !== undefined && existing !== route.scheme) {
            throw new ManagementError('conflict', `verification scheme mismatch for ${route.provider}`);
          }
          schemesByProvider.set(route.provider, route.scheme);
        }
        if (route.providerCredentialId !== undefined) {
          const credential = configuration.providerCredentials.find(item => item.id === route.providerCredentialId);
          const usableCredentials = configuration.providerCredentials.filter(
            item =>
              item.accountId === configuration.account.id &&
              item.tenantId === configuration.tenant.id &&
              item.provider === route.provider &&
              (item.status === 'live' ||
                (item.status === 'overlap' && item.overlapUntil !== undefined && item.overlapUntil > now)),
          );
          if (
            credential === undefined ||
            credential.accountId !== configuration.account.id ||
            credential.tenantId !== configuration.tenant.id ||
            credential.provider !== route.provider ||
            usableCredentials.length === 0
          ) {
            throw new ManagementError('forbidden', 'route provider credential ownership mismatch');
          }
        }
        for (const endpoint of endpoints) {
          validateEndpointTarget(endpoint.target, configuration.tenant.source);
          const credential = configuration.endpointSigningCredentials.find(
            item => item.id === endpoint.signingCredentialId,
          );
          if (
            credential === undefined ||
            credential.accountId !== configuration.account.id ||
            credential.tenantId !== configuration.tenant.id ||
            credential.endpointId !== endpoint.id ||
            credential.status !== 'live'
          ) {
            throw new ManagementError('forbidden', 'endpoint signing credential ownership mismatch');
          }
          assertSecretPointer(credential.secretPointer);
        }
      }
      for (const credential of configuration.providerCredentials) {
        assertSecretPointer(credential.secretPointer);
      }
    }
  }
}

export class InMemoryLandscapeConfigWriter implements LandscapeConfigWriter {
  readonly #documents = new Map<string, LandscapeConfigDocument>();
  readonly #current = new Map<string, number>();
  readonly #retained = new Map<string, Date>();

  public async readActiveConfiguration(landscape: string): Promise<ActiveLandscapeConfiguration | undefined> {
    const generation = this.#current.get(landscape);
    if (generation === undefined) return undefined;
    const document = this.#documents.get(`${landscape}:${generation}`);
    if (document === undefined) return undefined;
    return {
      generation,
      landscape,
      contentHash: document.contentHash,
      tenants: document.tenants.map(tenant => ({
        tenantId: tenant.tenantId,
        routes: tenant.routes,
      })),
    };
  }

  public async writeCompleteGeneration(document: LandscapeConfigDocument): Promise<void> {
    this.#documents.set(`${document.landscape}:${document.generation}`, structuredClone(document));
  }

  public async flipGeneration(
    landscape: string,
    generation: number,
    contentHash: string,
  ): Promise<{ activated: boolean; acknowledged: boolean }> {
    const document = this.#documents.get(`${landscape}:${generation}`);
    if (document === undefined || document.contentHash !== contentHash) {
      throw new Error('complete generation was not written');
    }
    this.#current.set(landscape, generation);
    return { activated: true, acknowledged: true };
  }

  public async retainPreviousGeneration(landscape: string, generation: number, until: Date): Promise<void> {
    if (this.#documents.has(`${landscape}:${generation}`)) {
      this.#retained.set(`${landscape}:${generation}`, new Date(until.getTime()));
    }
  }

  public document(landscape: string, generation: number): LandscapeConfigDocument | undefined {
    return structuredClone(this.#documents.get(`${landscape}:${generation}`));
  }

  public currentGeneration(landscape: string): number | undefined {
    return this.#current.get(landscape);
  }

  public retainedUntil(landscape: string, generation: number): Date | undefined {
    return structuredClone(this.#retained.get(`${landscape}:${generation}`));
  }
}
