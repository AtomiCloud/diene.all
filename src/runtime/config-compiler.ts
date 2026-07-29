import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type {
  Clock,
  CompiledEndpoint,
  CompiledRoute,
  CompiledTenant,
  ConfigSnapshotSource,
  DeliveryFailure,
  EndpointRefresher,
  EndpointRefreshRequest,
  LandscapeRuntimeConfig,
  RegistrationSnapshot,
  RuntimeConfigStore,
  RuntimeTelemetry,
  StorageFailure,
} from '../domain/index.ts';
import { DEDUP_WINDOW_SECONDS } from '../domain/index.ts';
import {
  boundedJsonDocumentByteLength,
  MAX_CONFIG_DOCUMENT_BYTES,
  registrationSnapshotSchema,
  runtimeConfigBoundsFailure,
} from './config.ts';

const orphanGraceMs = DEDUP_WINDOW_SECONDS * 1_000;
const DEFAULT_CONFIG_GENERATION_GRACE_MS = 5 * 60 * 1_000;

const storageFailure = (
  operation: string,
  message: string,
  code: StorageFailure['code'] = 'unavailable',
): StorageFailure => ({ code, operation, message });

const canonicalPath = (slug: string, routePath: string): string => `/t/${slug}${routePath}`;

type SnapshotEndpoint = RegistrationSnapshot['tenants'][number]['routes'][number]['endpoints'][number];
type SnapshotRoute = RegistrationSnapshot['tenants'][number]['routes'][number];

const compileEndpoint = (landscape: string, endpoint: SnapshotEndpoint): CompiledEndpoint => {
  const localUrl = endpoint.localUrls[landscape];
  if (localUrl !== undefined) {
    return {
      id: endpoint.id,
      address: localUrl,
      addressKind: 'local',
      canonicalUrl: endpoint.canonicalUrl,
      signingSecretRef: endpoint.signingSecretRef,
    };
  }

  return {
    id: endpoint.id,
    address: endpoint.canonicalUrl,
    addressKind: endpoint.targetKind === 'external' ? 'external' : 'canonical',
    canonicalUrl: endpoint.canonicalUrl,
    signingSecretRef: endpoint.signingSecretRef,
  };
};

const compileRoute = (landscape: string, slug: string, route: SnapshotRoute): CompiledRoute => ({
  id: route.id,
  path: route.path,
  canonicalPath: canonicalPath(slug, route.path),
  provider: route.provider,
  registeredUrl: route.registeredUrl,
  ...(route.verificationSecretRef === undefined ? {} : { verificationSecretRef: route.verificationSecretRef }),
  endpoints: route.endpoints.map(endpoint => compileEndpoint(landscape, endpoint)),
});

const orphanedRoutes = (
  previous: CompiledTenant | undefined,
  nextRoutes: readonly CompiledRoute[],
  nowMs: number,
): readonly CompiledRoute[] => {
  if (previous === undefined) {
    return [];
  }

  const nextProviders = new Set(nextRoutes.map(route => route.provider));
  const nextIds = new Set(nextRoutes.map(route => route.id));

  return previous.routes
    .filter(route => !nextIds.has(route.id) && !nextProviders.has(route.provider))
    .map(route => ({
      ...route,
      endpoints: [],
      orphanedUntilMs: route.orphanedUntilMs ?? nowMs + orphanGraceMs,
    }))
    .filter(route => (route.orphanedUntilMs ?? 0) > nowMs);
};

/**
 * Q-WH13 owner: this in-process Mercury compiler is the sole writer of cfg:*
 * generations. Its snapshot source may be Neon/CR-backed, but intake never is.
 */
export class MercuryConfigCompiler implements EndpointRefresher {
  constructor(
    readonly landscape: string,
    readonly source: ConfigSnapshotSource,
    readonly store: RuntimeConfigStore,
    readonly clock: Clock,
    readonly telemetry: RuntimeTelemetry,
    readonly generationGraceMs = DEFAULT_CONFIG_GENERATION_GRACE_MS,
  ) {}

  async compile(): Promise<Result<LandscapeRuntimeConfig, StorageFailure>> {
    const snapshotResult = await this.source.read();
    if (await snapshotResult.isErr()) {
      return Err(await snapshotResult.unwrapErr());
    }

    const snapshot = await snapshotResult.unwrap();
    if (boundedJsonDocumentByteLength(snapshot, MAX_CONFIG_DOCUMENT_BYTES) > MAX_CONFIG_DOCUMENT_BYTES) {
      return Err(
        storageFailure(
          'compile-config',
          `registration snapshot exceeds ${MAX_CONFIG_DOCUMENT_BYTES} bytes`,
          'invalid-data',
        ),
      );
    }

    const parsed = registrationSnapshotSchema.safeParse(snapshot);
    if (!parsed.success) {
      return Err(
        storageFailure(
          'compile-config',
          parsed.error.issues.map(issue => `${issue.path.join('.')}: ${issue.message}`).join('; '),
          'invalid-data',
        ),
      );
    }

    const activeResult = await this.store.readActive();
    if (await activeResult.isErr()) {
      return Err(await activeResult.unwrapErr());
    }

    const previous = await activeResult.unwrap();
    const generationResult = await this.store.reserveGeneration();
    if (await generationResult.isErr()) {
      return Err(await generationResult.unwrapErr());
    }
    const nowMs = this.clock.nowMs();
    const generation = await generationResult.unwrap();
    const tenants = parsed.data.tenants.map(tenant => {
      const routes = tenant.routes.map(route => compileRoute(this.landscape, tenant.slug, route));
      const preserved = orphanedRoutes(
        previous?.tenants.find(candidate => candidate.id === tenant.id),
        routes,
        nowMs,
      );
      return {
        id: tenant.id,
        slug: tenant.slug,
        registeredDomains: tenant.registeredDomains,
        intakeRps: tenant.intakeRps,
        intakeBurst: tenant.intakeBurst,
        retryWindowMs: tenant.retryWindowMs,
        routes: [...routes, ...preserved],
      } satisfies CompiledTenant;
    });
    const compiled: LandscapeRuntimeConfig = {
      generation,
      landscape: this.landscape,
      compiledAtMs: nowMs,
      sourceRevision: parsed.data.revision,
      tenants,
    };

    const boundsFailure = runtimeConfigBoundsFailure(compiled);
    if (boundsFailure !== null) {
      return Err(storageFailure('compile-config', boundsFailure, 'invalid-data'));
    }

    const staged = await this.store.stage(compiled);
    if (await staged.isErr()) {
      return Err(await staged.unwrapErr());
    }

    const activated = await this.store.activate(
      generation,
      previous?.generation ?? null,
      previous === null ? undefined : nowMs + Math.max(0, this.generationGraceMs),
    );
    if (await activated.isErr()) {
      await this.store.discard(generation);
      return Err(await activated.unwrapErr());
    }

    for (const tenant of tenants) {
      for (const route of tenant.routes) {
        if (route.orphanedUntilMs !== undefined) {
          await this.telemetry.record({
            name: 'orphaned-provider',
            attributes: {
              landscape: this.landscape,
              provider: route.provider,
              route: route.id,
              tenant: tenant.id,
            },
          });
        }
      }
    }

    const expired = await this.store.discardExpired(nowMs);
    if (await expired.isErr()) {
      const cleanupFailure = await expired.unwrapErr();
      await this.telemetry.record({
        name: 'config.retention.failure',
        attributes: {
          landscape: this.landscape,
          operation: cleanupFailure.operation,
        },
      });
    }
    return Ok(compiled);
  }

  async refreshEndpoint(request: EndpointRefreshRequest): Promise<Result<CompiledEndpoint, DeliveryFailure>> {
    const compiled = await this.compile();
    if (await compiled.isErr()) {
      return Err({
        code: 'config-unavailable',
        message: (await compiled.unwrapErr()).message,
      });
    }

    const config = await compiled.unwrap();
    const endpoint = config.tenants
      .find(tenant => tenant.id === request.tenantId)
      ?.routes.find(route => route.id === request.routeId)
      ?.endpoints.find(candidate => candidate.id === request.endpointId);
    if (endpoint === undefined) {
      return Err({
        code: 'config-unavailable',
        message: 'refreshed endpoint registration is absent',
      });
    }
    return Ok(endpoint);
  }
}
