import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type {
  DeliveryFailure,
  EndpointRefresher,
  EndpointRefreshRequest,
  LandscapeRuntimeConfig,
  CompiledEndpoint as RuntimeCompiledEndpoint,
} from '../domain/index.ts';
import type { ActiveLandscapeConfiguration, LandscapeConfigWriter, MercuryConfigurationCompiler } from './compiler.ts';
import { ManagementError } from './errors.ts';
import type { LandscapeConfigDocument, LandscapeTopology } from './types.ts';

export function toLandscapeRuntimeConfig(document: LandscapeConfigDocument): LandscapeRuntimeConfig {
  const compiledAtMs = Date.parse(document.createdAt);
  if (!Number.isFinite(compiledAtMs)) {
    throw new ManagementError('invalid', 'compiled configuration has an invalid creation timestamp');
  }
  const tenants = document.tenants.map(tenant => ({
    id: tenant.tenantId,
    slug: tenant.intakeSlug,
    registeredDomains: tenant.domains.map(domain => domain.hostname),
    intakeRps: tenant.quota.intakeRps,
    intakeBurst: tenant.quota.burst,
    retryWindowMs: tenant.quota.retryWindowSeconds * 1000,
    routes: tenant.routes.map(route => ({
      id: route.routeId,
      path: route.path,
      canonicalPath: `/t/${tenant.intakeSlug}${route.path}`,
      provider: route.provider,
      registeredUrl: route.registeredUrl,
      ...(route.providerCredentialPointers.length === 0
        ? {}
        : {
            verificationSecretRef: route.providerCredentialPointers[0],
            verificationSecretRefs: route.providerCredentialPointers,
          }),
      endpoints: route.endpoints.map(endpoint => ({
        id: endpoint.endpointId,
        address: endpoint.address,
        addressKind: endpoint.addressKind,
        canonicalUrl: endpoint.canonicalUrl,
        signingSecretRef: endpoint.signingSecretPointer,
      })),
      ...(route.orphanedUntilMs === undefined ? {} : { orphanedUntilMs: route.orphanedUntilMs }),
    })),
  }));
  return {
    generation: document.generation,
    landscape: document.landscape,
    compiledAtMs,
    sourceRevision: document.contentHash,
    tenants,
  };
}

/**
 * Landscape-local generation target. A production implementation owns exactly
 * one runtime store; it does not fan writes across landscapes.
 */
export interface RuntimeGenerationTarget {
  readonly landscape: string;
  readActive(): Promise<LandscapeRuntimeConfig | null>;
  stageComplete(config: LandscapeRuntimeConfig): Promise<void>;
  compareAndSwapActive(generation: number, expectedPreviousGeneration: number | null): Promise<boolean>;
  requestRetention(generation: number, until: Date): Promise<void>;
}

interface StagedGeneration {
  expectedPreviousGeneration: number | null;
  contentHash: string;
}

/**
 * Production seam from Mercury's Neon compiler to one landscape runtime.
 * Staging, pointer CAS, read-back acknowledgement, and grace retention remain
 * local operations on the injected target.
 */
export class LocalLandscapeConfigWriter implements LandscapeConfigWriter {
  readonly #staged = new Map<number, StagedGeneration>();

  public constructor(private readonly target: RuntimeGenerationTarget) {}

  public async readActiveConfiguration(landscape: string): Promise<ActiveLandscapeConfiguration | undefined> {
    this.assertLandscape(landscape);
    const active = await this.target.readActive();
    if (active === null) return undefined;
    return {
      generation: active.generation,
      landscape: active.landscape,
      contentHash: active.sourceRevision,
      tenants: active.tenants.map(tenant => ({
        tenantId: tenant.id,
        routes: tenant.routes.map(route => {
          const withCredentialSet = route as typeof route & { verificationSecretRefs?: readonly string[] };
          return {
            routeId: route.id,
            path: route.path,
            registeredUrl: route.registeredUrl,
            provider: route.provider,
            providerCredentialPointers:
              withCredentialSet.verificationSecretRefs ??
              (route.verificationSecretRef === undefined ? [] : [route.verificationSecretRef]),
            endpoints: route.endpoints.map(endpoint => ({
              endpointId: endpoint.id,
              address: endpoint.address,
              addressKind: endpoint.addressKind,
              canonicalUrl: endpoint.canonicalUrl,
              signingSecretPointer: endpoint.signingSecretRef,
            })),
            ...(route.orphanedUntilMs === undefined ? {} : { orphanedUntilMs: route.orphanedUntilMs }),
          };
        }),
      })),
    };
  }

  public async writeCompleteGeneration(document: LandscapeConfigDocument): Promise<void> {
    this.assertLandscape(document.landscape);
    const runtime = toLandscapeRuntimeConfig(document);
    const previous = await this.target.readActive();
    await this.target.stageComplete(runtime);
    this.#staged.set(document.generation, {
      expectedPreviousGeneration: previous?.generation ?? null,
      contentHash: document.contentHash,
    });
  }

  public async flipGeneration(
    landscape: string,
    generation: number,
    contentHash: string,
  ): Promise<{ activated: boolean; acknowledged: boolean }> {
    this.assertLandscape(landscape);
    const staged = this.#staged.get(generation);
    if (staged === undefined || staged.contentHash !== contentHash) {
      throw new ManagementError('compiler_failed', 'generation was not completely staged for this landscape');
    }
    const swapped = await this.target.compareAndSwapActive(generation, staged.expectedPreviousGeneration);
    if (!swapped) {
      throw new ManagementError('compiler_failed', 'active runtime generation changed during compilation');
    }
    let acknowledged = false;
    try {
      const active = await this.target.readActive();
      acknowledged =
        active?.generation === generation &&
        active.sourceRevision === contentHash &&
        active.landscape === this.target.landscape;
    } catch {
      acknowledged = false;
    }
    this.#staged.delete(generation);
    return { activated: true, acknowledged };
  }

  public async retainPreviousGeneration(landscape: string, generation: number, until: Date): Promise<void> {
    this.assertLandscape(landscape);
    await this.target.requestRetention(generation, until);
  }

  private assertLandscape(landscape: string): void {
    if (landscape !== this.target.landscape) {
      throw new ManagementError('invalid', `local writer owns ${this.target.landscape}, not ${landscape}`);
    }
  }
}

/**
 * Delivery's one permitted 421 refresh: recompile the configured local
 * landscape, then return only the same tenant/route/endpoint registration.
 */
export class MercuryManagementEndpointRefresher implements EndpointRefresher {
  public constructor(
    private readonly landscape: string,
    private readonly topology: LandscapeTopology,
    private readonly compiler: MercuryConfigurationCompiler,
  ) {}

  public async refreshEndpoint(
    request: EndpointRefreshRequest,
  ): Promise<Result<RuntimeCompiledEndpoint, DeliveryFailure>> {
    if (this.topology.landscapes.length !== 1 || this.topology.landscapes[0] !== this.landscape) {
      return Err({
        code: 'config-unavailable',
        message: 'endpoint refresh topology must contain only the local landscape',
      });
    }
    try {
      const result = await this.compiler.compileAndPublish(this.topology);
      const document = result.documents.find(candidate => candidate.landscape === this.landscape);
      if (document === undefined) {
        return Err({
          code: 'config-unavailable',
          message: 'local landscape generation is absent',
        });
      }
      const endpoint = toLandscapeRuntimeConfig(document)
        .tenants.find(tenant => tenant.id === request.tenantId)
        ?.routes.find(route => route.id === request.routeId)
        ?.endpoints.find(candidate => candidate.id === request.endpointId);
      if (endpoint === undefined) {
        return Err({
          code: 'config-unavailable',
          message: 'refreshed endpoint registration is absent',
        });
      }
      return Ok(endpoint);
    } catch (error) {
      return Err({
        code: 'config-unavailable',
        message: error instanceof Error ? error.message : String(error),
      });
    }
  }
}
