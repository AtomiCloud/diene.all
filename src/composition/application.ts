import { X509Certificate } from 'node:crypto';
import type { OtelRuntime } from '@atomicloud/diene.otel';
import type { ErrorPortalConfig } from '@atomicloud/diene.problems';
import type { Result } from '@atomicloud/diene.result';
import type { Hono } from 'hono';
import Redis from 'ioredis';
import postgres from 'postgres';
import { Registry } from 'prom-client';
import {
  type ConsoleActionAuditor,
  type ConsoleActionAuditRequest,
  type ConsoleIncidentReporter,
  type ConsolePreviewVisibility,
  type ConsoleResult,
  ConsoleSessionManager,
  type ConsoleSessionPolicy,
  createConsoleApp,
  HttpConsoleOperations,
  MercuryManagementConsoleGateway,
  RedisConsoleLoginRateLimiter,
  RedisConsoleSessionRepository,
  SignedConsoleAuthorizationExchange,
  SignedConsoleNativeAuthorizer,
  WebCryptoConsoleRequestSecurity,
  WebCryptoConsoleSessionCryptography,
} from '../console/index.ts';
import { DeliveryEngine, FetchDeliveryTransport } from '../delivery/index.ts';
import {
  type Clock,
  type IdentifierFactory,
  InternalDeliverySigner,
  type LandscapeRuntimeConfig,
  MERCURY_MAX_REQUEST_BODY_BYTES,
  NameBlindRouteResolver,
  type SecretReader,
} from '../domain/index.ts';
import { createIntakeHandler, IntakeHttpAdapter, IntakeProblemCatalog } from '../http/intake/index.ts';
import { createLandscapeOperationsApi } from '../http/landscape/index.ts';
import { createManagementApi } from '../http/management/index.ts';
import {
  type CircuitCommander,
  DnsDomainOwnershipVerifier,
  type DomainCertificateReadinessProbe,
  type LandscapeTopology,
  LocalLandscapeConfigWriter,
  ManagementService,
  MercuryConfigurationCompiler,
  MercuryManagementEndpointRefresher,
  PostgresManagementRepository,
  type ReplayDispatcher,
  type ReplayScope,
} from '../management/index.ts';
import { toLandscapeRuntimeConfig } from '../management/runtime-generation.ts';
import {
  type AppleBackfillOptions,
  type AppleNotificationHistoryClient,
  AppleServerApiBackfillRunner,
  createAppleAppStoreNotificationHistoryClient,
  createGoogleServiceAccountOAuthAccessTokenReader,
  FetchGooglePubSubAdministrationClient,
  type GoogleOAuthAccessTokenReader,
  type GooglePlayRtdnReconcilerOptions,
  GooglePlayRtdnSubscriptionReconciler,
  type GooglePubSubAdministrationClient,
  type GooglePubSubRestClientOptions,
  PostgresAppleBackfillStateStore,
} from '../provider-operations/index.ts';
import { MercuryProviderVerifierRegistry, validateProviderConfiguration } from '../providers/index.ts';
import {
  ArchiveRetentionLoopJob,
  DueDeliveryLoopJob,
  IntakeEngine,
  MercuryRuntimeSupervisor,
  MercuryTelemetry,
  MountedSecretReader,
  RandomIdentifierFactory,
  RuntimeConfigTenantSource,
  SystemClock,
} from '../runtime/index.ts';
import {
  createTigrisArchiveStore,
  EventRetentionManager,
  RedisFlowStore,
  RedisRuntimeConfigStore,
} from '../storage/index.ts';
import { loadConsoleAuthorizationKeys } from './authorization-keys.ts';
import type { MercuryConfig } from './config.ts';
import { createMercuryHttpApplication, type MercuryDependencyState, type MercuryReadinessReport } from './http.ts';
import { ConsoleLandscapeOperationsAuthenticator } from './landscape-auth.ts';
import { runMercuryMigrations } from './migrations.ts';
import { MercuryMaintenanceLoopJob, RuntimeStoreGenerationTarget } from './runtime.ts';
import {
  readRequiredSecret,
  readRequiredSecretText,
  SecretBackedProviderConfigurationReader,
  VaultPointerSecretReader,
} from './secrets.ts';
import { initializeMercuryTelemetry } from './telemetry.ts';

type Sql = ReturnType<typeof postgres>;

const DEFAULT_DELIVERY_INTERVAL_MS = 1_000;
const DEFAULT_RETENTION_INTERVAL_MS = 300_000;
const DEFAULT_RECONCILE_INTERVAL_MS = 60_000;
const DEFAULT_DELIVERY_TIMEOUT_MS = 10_000;
const DEFAULT_CONSOLE_AUTHORIZATION_TTL_SECONDS = 120;
const DEFAULT_LOGIN_ATTEMPTS = 5;
const DEFAULT_GLOBAL_LOGIN_ATTEMPTS = 200;
const DEFAULT_LOGIN_WINDOW_SECONDS = 300;
const RECONCILE_LEASE_KEY = 'cfg:reconcile-lease';
const MERCURY_PROBLEM_PORTAL: ErrorPortalConfig = {
  scheme: 'https',
  host: 'problems.atomi.cloud',
  landscape: 'serving',
  platform: 'mercury',
  service: 'webhook',
  module: 'hooks',
};
const MINIMUM_CONSOLE_SESSION_SECRET_BYTES = 32;

const defaultSessionPolicy: ConsoleSessionPolicy = {
  idleTtlSeconds: 1_800,
  absoluteTtlSeconds: 43_200,
  rotationIntervalSeconds: 900,
};

/**
 * Stable logical names for the platform key material. Each one is bound to an
 * absolute file from the `security` config block through an explicit
 * mounted-secret mapping, so no caller ever names a host path.
 */
export interface MercurySecretReferences {
  readonly consoleSessionSecret: string;
  readonly managementBootstrapToken: string;
  readonly consoleAuthorizationPrivateKey: string;
  readonly consoleAuthorizationPublicKey: string;
  readonly archiveAccessKeyId: string;
  readonly archiveSecretAccessKey: string;
}

export const defaultSecretReferences: MercurySecretReferences = {
  consoleSessionSecret: 'console-session',
  managementBootstrapToken: 'management-bootstrap-token',
  consoleAuthorizationPrivateKey: 'console-authorization-private-key',
  consoleAuthorizationPublicKey: 'console-authorization-public-key',
  archiveAccessKeyId: 'archive-access-key-id',
  archiveSecretAccessKey: 'archive-secret-access-key',
};

export interface MercuryServerHandle {
  stop(closeActiveConnections?: boolean): unknown;
}

export interface MercuryServerOptions {
  readonly hostname: string;
  readonly port: number;
  /** Product-sized body ceiling enforced by the server before route lookup. */
  readonly maxRequestBodySize: number;
  readonly fetch: (request: Request) => Promise<Response>;
}

export type MercuryServerFactory = (options: MercuryServerOptions) => MercuryServerHandle;

/** Test override for the App Store Server API history client. */
export interface MercuryAppleBackfillSeam {
  readonly history?: AppleNotificationHistoryClient;
}

/** Test overrides for the Google Pub/Sub administration path. */
export interface MercuryGoogleRtdnSeam {
  readonly accessTokens?: GoogleOAuthAccessTokenReader;
  readonly client?: GooglePubSubAdministrationClient;
  readonly restOptions?: GooglePubSubRestClientOptions;
}

/**
 * Every external dependency the production root creates is injectable so unit
 * tests can compose the whole product without Redis, Postgres, Tigris, or a
 * listening socket.
 */
export interface MercuryCompositionSeams {
  readonly createRedis?: (url: string) => Redis;
  readonly createSql?: (url: string) => Sql;
  readonly createTelemetry?: (config: MercuryConfig) => OtelRuntime;
  readonly createSecretReader?: (root: string, mapping: Readonly<Record<string, string>>) => SecretReader;
  readonly createArchiveStore?: (input: {
    readonly bucket: string;
    readonly endpoint: string;
    readonly region: string;
    readonly accessKeyId: string;
    readonly secretAccessKey: string;
  }) => ConstructorParameters<typeof EventRetentionManager>[1];
  readonly serve?: MercuryServerFactory;
  readonly fetch?: typeof globalThis.fetch;
  readonly clock?: Clock;
  readonly identifiers?: IdentifierFactory;
  readonly registry?: Registry;
  readonly secretReferences?: Partial<MercurySecretReferences>;
  readonly secretRoot?: string;
  readonly topology?: LandscapeTopology;
  readonly sessionPolicy?: ConsoleSessionPolicy;
  readonly deliveryTimeoutMs?: number;
  readonly deliveryIntervalMs?: number;
  readonly retentionIntervalMs?: number;
  readonly reconcileIntervalMs?: number;
  readonly consoleAuthorizationTtlSeconds?: number;
  readonly appleBackfill?: MercuryAppleBackfillSeam;
  readonly googleRtdn?: MercuryGoogleRtdnSeam;
}

export interface MercuryApplication {
  readonly config: MercuryConfig;
  readonly registry: Registry;
  readonly supervisor: MercuryRuntimeSupervisor;
  readonly router: Hono;
  fetch(request: Request): Promise<Response>;
  startupComplete(): boolean;
  readiness(): Promise<MercuryReadinessReport>;
  start(): Promise<void>;
  shutdown(): Promise<void>;
}

export interface MercuryDbInitResult {
  readonly migrations: readonly string[];
  readonly accountId: string;
  readonly credentialIssued: boolean;
}

/**
 * Mercury materializes only the landscape it is running in. The landscape list
 * is always this process's own; service coordinates come from trusted local
 * platform configuration and never from a management API caller.
 */
export function localLandscapeTopology(config: MercuryConfig): LandscapeTopology {
  const app = config('app');
  return {
    landscapes: [app.landscape],
    services: structuredClone(config('topology').services) as LandscapeTopology['services'],
  };
}

/** Landscape-local replay for management mutations; no cross-landscape fan-out. */
export class LocalReplayDispatcher implements ReplayDispatcher {
  constructor(
    readonly landscape: string,
    readonly delivery: DeliveryEngine,
  ) {}

  async dispatch(input: { landscape: string; tenantId: string; scope: ReplayScope; commandId: string }): Promise<void> {
    if (input.landscape !== this.landscape) {
      throw new Error('replay dispatch is confined to the local landscape');
    }
    const result =
      input.scope.kind === 'event'
        ? await this.delivery.replayEvent(input.scope.eventId)
        : await this.delivery.replayEndpointFailures(input.tenantId, input.scope.endpointId);
    if (await result.isErr()) {
      throw new Error(`replay dispatch failed: ${(await result.unwrapErr()).code}`);
    }
  }
}

/** Landscape-local circuit control backed by the same delivery engine. */
export class LocalCircuitCommander implements CircuitCommander {
  constructor(
    readonly landscape: string,
    readonly delivery: DeliveryEngine,
  ) {}

  async reenable(input: { landscape: string; tenantId: string; endpointId: string }): Promise<void> {
    this.assertLocal(input.landscape);
    const closed = await this.delivery.manualClose(input.tenantId, input.endpointId);
    if (await closed.isErr()) {
      throw new Error(`circuit re-enable failed: ${(await closed.unwrapErr()).code}`);
    }
  }

  async probe(input: { landscape: string; tenantId: string; endpointId: string }): Promise<boolean> {
    this.assertLocal(input.landscape);
    const probed = await this.delivery.probeEndpoint(input.tenantId, input.endpointId);
    // A negative probe is a legitimate command result; only an unusable
    // delivery path is reported as a failure to the management caller.
    if (await probed.isErr()) {
      throw new Error(`circuit probe failed: ${(await probed.unwrapErr()).code}`);
    }
    return probed.unwrap();
  }

  private assertLocal(landscape: string): void {
    if (landscape !== this.landscape) {
      throw new Error('circuit commands are confined to the local landscape');
    }
  }
}

/**
 * Persists a durable `ReplayAudit` before the console is allowed to dispatch a
 * landscape-local action. A rejected or failed write suppresses the action.
 */
export class ManagementReplayAuditor implements ConsoleActionAuditor {
  constructor(
    readonly repository: PostgresManagementRepository,
    readonly clock: Clock,
    readonly identifiers: IdentifierFactory,
  ) {}

  async accept(request: ConsoleActionAuditRequest): Promise<ConsoleResult<void>> {
    const tenants = request.authorization.scope.tenants;
    if (tenants !== '*' && !tenants.includes(request.tenantId)) {
      return {
        ok: false,
        error: {
          kind: 'forbidden',
          title: 'Tenant scope rejected',
          detail: 'The verified authorization does not cover this tenant.',
        },
      };
    }
    try {
      await this.repository.saveReplayAudit({
        id: this.identifiers.create(),
        accountId: request.authorization.accountId,
        tenantId: request.tenantId,
        landscape: request.landscape,
        scope:
          request.target.kind === 'event-replay'
            ? { kind: 'event', eventId: request.target.eventId }
            : { kind: 'endpoint', endpointId: request.target.endpointId },
        reason: request.context.reason,
        commandId: request.context.requestId,
        requestedAt: new Date(this.clock.nowMs()),
      });
      return { ok: true, value: undefined };
    } catch {
      return {
        ok: false,
        error: {
          kind: 'unavailable',
          title: 'Action audit unavailable',
          detail: 'The action could not be durably recorded; it was not dispatched.',
        },
      };
    }
  }
}

/** Reports console incidents without ever echoing request bodies or secrets. */
export class LoggingConsoleIncidentReporter implements ConsoleIncidentReporter {
  constructor(readonly telemetry: MercuryTelemetry) {}

  async report(input: {
    readonly requestId: string;
    readonly method: string;
    readonly path: string;
    readonly error: unknown;
  }): Promise<void> {
    // Only the request coordinates are recorded; the raised value may carry
    // caller-supplied material and is never serialized.
    await this.telemetry.record({
      name: 'console.incident',
      attributes: { method: input.method, path: input.path, requestId: input.requestId },
    });
  }
}

const positiveInteger = (value: number, label: string): number => {
  if (!Number.isSafeInteger(value) || value < 1) {
    throw new Error(`${label} must be a positive integer number of milliseconds`);
  }
  return value;
};

const withTimeout = async (work: Promise<unknown>, milliseconds: number): Promise<boolean> => {
  let timeout: ReturnType<typeof setTimeout> | undefined;
  const expiry = new Promise<false>(resolve => {
    timeout = setTimeout(() => resolve(false), milliseconds);
  });
  try {
    return await Promise.race([work.then(() => true), expiry]);
  } finally {
    if (timeout !== undefined) {
      clearTimeout(timeout);
    }
  }
};

const activeGeneration = async (store: RedisRuntimeConfigStore): Promise<LandscapeRuntimeConfig | null> => {
  const result = await store.readActive();
  return (await result.isErr()) ? null : await result.unwrap();
};

/** Minimal per-route projection a generation preflight needs to reason about. */
export interface ProviderReadinessRoute {
  readonly provider: string;
  /** Ordered verification credential references (dual-live rotation aware). */
  readonly verificationSecretRefs?: readonly string[];
  /** Singular fallback for callers that carry a single verification reference. */
  readonly verificationSecretRef?: string;
  readonly endpoints: readonly { readonly signingSecretRef: string }[];
}

/** Read seams a generation preflight resolves references against. */
export interface ProviderReadinessReaders {
  readonly providerConfigurations: { read(reference: string): Promise<unknown> };
  readonly deliverySecrets: {
    read(reference: string): Promise<Result<Uint8Array, { readonly message: string }>>;
  };
}

/**
 * Preflights a would-be-active generation's provider readiness (H2 seam).
 *
 * Rejects — the throw the management compiler awaits immediately before its CAS,
 * so a bad generation is never activated and the previous active runtime is
 * preserved — when any route names a provider outside the exact seven, carries a
 * missing/malformed provider-specific verification configuration, or references
 * an unreadable endpoint signing secret. `validateProviderConfiguration` owns the
 * exact-seven set and each provider-specific credential shape. Also run at every
 * reconcile against the active generation as defense in depth.
 */
export async function preflightProviderReadiness(
  routes: readonly ProviderReadinessRoute[],
  readers: ProviderReadinessReaders,
): Promise<void> {
  for (const route of routes) {
    const references =
      route.verificationSecretRefs ?? (route.verificationSecretRef === undefined ? [] : [route.verificationSecretRef]);
    const configurations =
      references.length === 0
        ? [undefined]
        : await Promise.all(
            references.map(reference => readers.providerConfigurations.read(reference).catch(() => undefined)),
          );
    for (const configuration of configurations) {
      const validation = validateProviderConfiguration(route.provider, configuration);
      if (!validation.ok) {
        throw new Error(`provider readiness preflight rejected ${route.provider}: ${validation.failure.code}`);
      }
    }
    for (const endpoint of route.endpoints) {
      const material = await readers.deliverySecrets.read(endpoint.signingSecretRef);
      if (await material.isErr()) {
        throw new Error('a compiled endpoint signing secret is unavailable for the pending generation');
      }
      (await material.unwrap()).fill(0);
    }
  }
}

/**
 * Fail-closed custom-domain certificate-readiness probe.
 *
 * A domain becomes publishable (`active`) only when real leaf certificate
 * material for it has been centrally fanned into the root-confined secret mount
 * at its derived pointer. The probe reads that pointer and returns true only
 * when the material parses as an X.509 certificate whose validity window
 * contains the current clock and whose SAN/CN matches the hostname. Missing,
 * empty, malformed, expired, or wrong-host material — and any read failure —
 * all return false, so DNS proof alone never publishes a domain. Read bytes are
 * always zeroed.
 *
 * Note: this attests that certificate material exists and matches; gateway /
 * HTTPRoute serving readiness for that certificate is a separate, externally
 * owned authority and is intentionally out of scope here.
 */
export function createCertificateReadinessProbe(
  reader: { read(reference: string): Promise<Result<Uint8Array, { readonly message: string }>> },
  now: () => Date,
): DomainCertificateReadinessProbe {
  return {
    isReady: async ({ hostname, certificateSecretPointer }): Promise<boolean> => {
      const material = await reader.read(certificateSecretPointer);
      if (await material.isErr()) {
        return false;
      }
      const bytes = await material.unwrap();
      try {
        if (bytes.byteLength === 0) {
          return false;
        }
        const certificate = new X509Certificate(Buffer.from(bytes));
        const validFrom = new Date(certificate.validFrom);
        const validTo = new Date(certificate.validTo);
        if (Number.isNaN(validFrom.getTime()) || Number.isNaN(validTo.getTime())) {
          return false;
        }
        const current = now();
        if (current < validFrom || current > validTo) {
          return false;
        }
        return certificate.checkHost(hostname) !== undefined;
      } catch {
        return false;
      } finally {
        bytes.fill(0);
      }
    },
  };
}

const projectGenerationRoutes = (generation: LandscapeRuntimeConfig): ProviderReadinessRoute[] =>
  generation.tenants.flatMap(tenant =>
    tenant.routes.map(route => ({
      provider: route.provider,
      // Preserve the full ordered live-then-overlap credential set so reconcile
      // preflight validates every reference the runtime generation carries, not
      // just the newest one. Singular fallback covers routes compiled before the
      // ordered set existed.
      ...(route.verificationSecretRefs === undefined ? {} : { verificationSecretRefs: route.verificationSecretRefs }),
      ...(route.verificationSecretRef === undefined ? {} : { verificationSecretRef: route.verificationSecretRef }),
      endpoints: route.endpoints.map(endpoint => ({ signingSecretRef: endpoint.signingSecretRef })),
    })),
  );

const secretReferencesFrom = (overrides: Partial<MercurySecretReferences> | undefined): MercurySecretReferences => ({
  ...defaultSecretReferences,
  ...overrides,
});

/**
 * Builds every production dependency and mounts the single Hono surface.
 * Security material is read and pair-checked here so a missing or malformed
 * input fails closed before the process ever accepts traffic.
 */
export async function createMercuryApplication(
  config: MercuryConfig,
  seams: MercuryCompositionSeams = {},
): Promise<MercuryApplication> {
  const cleanups: Array<() => Promise<void>> = [];
  try {
    return await composeMercuryApplication(config, seams, cleanups);
  } catch (error) {
    // A rejected security input must not strand telemetry, Redis, or Postgres.
    for (const release of cleanups.reverse()) {
      await release().catch(() => undefined);
    }
    throw error;
  }
}

async function composeMercuryApplication(
  config: MercuryConfig,
  seams: MercuryCompositionSeams,
  cleanups: Array<() => Promise<void>>,
): Promise<MercuryApplication> {
  const app = config('app');
  const storage = config('storage');
  const security = config('security');

  const deliveryTimeoutMs = positiveInteger(seams.deliveryTimeoutMs ?? DEFAULT_DELIVERY_TIMEOUT_MS, 'delivery timeout');
  if (deliveryTimeoutMs > app.shutdownGraceMs) {
    throw new Error('delivery timeout must not exceed the configured shutdown grace period');
  }
  const deliveryIntervalMs = positiveInteger(
    seams.deliveryIntervalMs ?? DEFAULT_DELIVERY_INTERVAL_MS,
    'delivery loop interval',
  );
  const retentionIntervalMs = positiveInteger(
    seams.retentionIntervalMs ?? DEFAULT_RETENTION_INTERVAL_MS,
    'retention loop interval',
  );
  const reconcileIntervalMs = positiveInteger(
    seams.reconcileIntervalMs ?? DEFAULT_RECONCILE_INTERVAL_MS,
    'configuration reconcile interval',
  );

  const clock = seams.clock ?? new SystemClock();
  const identifiers = seams.identifiers ?? new RandomIdentifierFactory();
  const registry = seams.registry ?? new Registry();
  const references = secretReferencesFrom(seams.secretReferences);
  const secretRoot = seams.secretRoot ?? security.endpointSecretRoot;
  const topology = seams.topology ?? localLandscapeTopology(config);
  if (topology.landscapes.length !== 1 || topology.landscapes[0] !== app.landscape) {
    throw new Error('Mercury compiles only its own landscape topology');
  }

  const otel = (seams.createTelemetry ?? initializeMercuryTelemetry)(config);
  cleanups.push(async () => {
    await otel.flush().catch(() => undefined);
    await otel.shutdown().catch(() => undefined);
  });
  const telemetry = new MercuryTelemetry(otel.logger, otel.traceEmitter, registry);

  const createSecretReader =
    seams.createSecretReader ?? ((root, mapping) => new MountedSecretReader({ root, mapping }));
  const platformSecrets = createSecretReader(secretRoot, {
    [references.consoleSessionSecret]: security.consoleSessionSecretFile,
    [references.managementBootstrapToken]: security.managementBootstrapTokenFile,
    [references.consoleAuthorizationPrivateKey]: security.consoleAuthorizationPrivateKeyFile,
    [references.consoleAuthorizationPublicKey]: security.consoleAuthorizationPublicKeyFile,
    [references.archiveAccessKeyId]: security.archiveAccessKeyIdFile,
    [references.archiveSecretAccessKey]: security.archiveSecretAccessKeyFile,
  });
  const providerSecrets = createSecretReader(security.providerSecretRoot, {});
  // Compiled tenant credential pointers are vault pointers (`/stripe.json`);
  // provider-operation refs configured by the platform are plain relative
  // names, so those read the root-confined reader directly.
  const providerConfigurations = new SecretBackedProviderConfigurationReader(
    new VaultPointerSecretReader(providerSecrets),
  );
  // Endpoint signing pointers are tenant-registered input. They resolve only
  // beneath the endpoint mount and must never reach the platform key mapping.
  const deliverySecrets = new VaultPointerSecretReader(createSecretReader(security.endpointSecretRoot, {}));

  const consoleSessionSecret = await readRequiredSecret(
    platformSecrets,
    references.consoleSessionSecret,
    'console session secret',
    MINIMUM_CONSOLE_SESSION_SECRET_BYTES,
  );
  const consoleKeys = await loadConsoleAuthorizationKeys(
    platformSecrets,
    references.consoleAuthorizationPrivateKey,
    references.consoleAuthorizationPublicKey,
  );
  const archiveAccessKeyId = await readRequiredSecretText(
    platformSecrets,
    references.archiveAccessKeyId,
    'archive access key id',
  );
  const archiveSecretAccessKey = await readRequiredSecretText(
    platformSecrets,
    references.archiveSecretAccessKey,
    'archive secret access key',
  );

  const redis = (seams.createRedis ?? (url => new Redis(url, { maxRetriesPerRequest: 3 })))(storage.redisUrl);
  cleanups.push(async () => {
    await Promise.resolve(redis.quit()).catch(() => undefined);
  });
  const sql = (seams.createSql ?? (url => postgres(url, { max: 8 })))(storage.postgresUrl);
  cleanups.push(async () => {
    await Promise.resolve(sql.end({ timeout: 5 })).catch(() => undefined);
  });

  const flow = new RedisFlowStore(app.landscape, redis);
  const runtimeConfig = new RedisRuntimeConfigStore(redis);
  const generationTarget = new RuntimeStoreGenerationTarget(app.landscape, runtimeConfig);

  const repository = new PostgresManagementRepository(sql);
  const compiler = new MercuryConfigurationCompiler(repository, new LocalLandscapeConfigWriter(generationTarget), {
    // H2 pre-CAS gate: the compiler awaits this on the fully staged document
    // immediately before flipGeneration/CAS. Projecting the document to its
    // runtime shape and running the provider-readiness preflight here means a
    // generation with an unsupported provider or missing/malformed
    // verification/signing credential is rejected BEFORE activation — the
    // previous active generation is preserved. `preflightActiveGeneration`
    // remains as post-activation defense in depth.
    preActivate: async document =>
      preflightProviderReadiness(projectGenerationRoutes(toLandscapeRuntimeConfig(document)), {
        providerConfigurations,
        deliverySecrets,
      }),
  });
  const refresher = new MercuryManagementEndpointRefresher(app.landscape, topology, compiler);

  const baseFetch = seams.fetch ?? globalThis.fetch;
  const delivery = new DeliveryEngine(
    flow,
    // The transport owns a bounded per-attempt timeout and reports a drained
    // shutdown as a cancellation rather than a retryable transport failure.
    new FetchDeliveryTransport(baseFetch, deliveryTimeoutMs),
    deliverySecrets,
    refresher,
    clock,
    new InternalDeliverySigner(),
    telemetry,
  );

  const management = new ManagementService(repository, {
    replayDispatcher: new LocalReplayDispatcher(app.landscape, delivery),
    circuitCommander: new LocalCircuitCommander(app.landscape, delivery),
    // Production custom-domain verification: resolve the traffic + _acme-challenge
    // CNAMEs (the verifier defaults to node DNS resolveCname). Certificate
    // readiness is a real fail-closed probe of the centrally fanned leaf
    // certificate at the derived pointer through the root-confined endpoint
    // secret reader, so a DNS-proven domain is published `active` only once
    // matching, unexpired certificate material actually exists — never on DNS
    // proof or arbitrary bytes alone.
    domainOwnershipVerifier: new DnsDomainOwnershipVerifier({
      certificateReadiness: createCertificateReadinessProbe(deliverySecrets, () => new Date(clock.nowMs())),
    }),
  });

  const verifiers = new MercuryProviderVerifierRegistry(providerConfigurations, {
    now: () => new Date(clock.nowMs()),
  });
  const intake = new IntakeEngine(
    runtimeConfig,
    flow,
    verifiers,
    new NameBlindRouteResolver(),
    clock,
    identifiers,
    telemetry,
  );
  // The published problem catalog identity is stable across landscapes; it
  // matches the chart/docs portal in http/intake/problems.ts exactly.
  const intakeProblems = new IntakeProblemCatalog(MERCURY_PROBLEM_PORTAL);
  const intakeHandler = createIntakeHandler(new IntakeHttpAdapter(intake, intakeProblems));

  const archive = (
    seams.createArchiveStore ??
    (input =>
      createTigrisArchiveStore(input.bucket, {
        endpoint: input.endpoint,
        region: input.region,
        accessKeyId: input.accessKeyId,
        secretAccessKey: input.secretAccessKey,
      }))
  )({
    bucket: storage.archiveBucket,
    endpoint: storage.archiveEndpoint,
    region: storage.archiveRegion,
    accessKeyId: archiveAccessKeyId,
    secretAccessKey: archiveSecretAccessKey,
  });
  const retention = new EventRetentionManager(flow, archive, clock, telemetry);
  const supervisor = new MercuryRuntimeSupervisor(
    app.landscape,
    { job: new DueDeliveryLoopJob(delivery, clock), intervalMs: deliveryIntervalMs },
    {
      job: new MercuryMaintenanceLoopJob(
        new ArchiveRetentionLoopJob(retention, new RuntimeConfigTenantSource(runtimeConfig)),
        runtimeConfig,
        clock,
      ),
      intervalMs: retentionIntervalMs,
    },
    telemetry,
  );

  const consoleClock = { now: (): Date => new Date(clock.nowMs()) };
  const requestSecurity = new WebCryptoConsoleRequestSecurity();
  const sessions = new ConsoleSessionManager(
    new RedisConsoleSessionRepository(redis, { clock: consoleClock }),
    new WebCryptoConsoleSessionCryptography(consoleSessionSecret),
    seams.sessionPolicy ?? defaultSessionPolicy,
  );
  consoleSessionSecret.fill(0);
  const consoleGateway = new MercuryManagementConsoleGateway(
    management,
    new RedisConsoleLoginRateLimiter(redis, {
      maxAttempts: DEFAULT_LOGIN_ATTEMPTS,
      globalMaxAttempts: DEFAULT_GLOBAL_LOGIN_ATTEMPTS,
      windowSeconds: DEFAULT_LOGIN_WINDOW_SECONDS,
    }),
  );
  const previewVisibility: ConsolePreviewVisibility = app.previewDeliveryVisible
    ? {
        state: 'visible',
        detail: 'Preview callback-delivery visibility is enabled for this landscape.',
        affectedLandscapes: [],
      }
    : {
        state: 'withheld-d11',
        detail: 'Preview callback-delivery visibility is withheld until D11 lands.',
        affectedLandscapes: [app.landscape],
      };
  const consoleApp = createConsoleApp(
    {
      clock: consoleClock,
      sessions,
      managementGateway: consoleGateway,
      authorization: new SignedConsoleAuthorizationExchange({
        clock: consoleClock,
        keyId: consoleKeys.keyId,
        issuer: security.managementIssuer,
        audience: security.managementAudience,
        signingKey: consoleKeys.privateKey,
        tokenIds: requestSecurity,
        ttlSeconds: seams.consoleAuthorizationTtlSeconds ?? DEFAULT_CONSOLE_AUTHORIZATION_TTL_SECONDS,
      }),
      operations: new HttpConsoleOperations(
        consoleGateway,
        new ManagementReplayAuditor(repository, clock, identifiers),
        { clock: consoleClock, fetch: baseFetch, previewVisibility },
      ),
      requestSecurity,
      incidentReporter: new LoggingConsoleIncidentReporter(telemetry),
    },
    { origin: app.publicOrigin },
  );

  const landscapeApi = createLandscapeOperationsApi({
    flow,
    delivery,
    config: runtimeConfig,
    // Product-owned archive lifecycle: the maintenance endpoint drives the same
    // production EventRetentionManager the retention loop uses — no second
    // manager, no synthetic result — gated by the distinct retention:run
    // capability.
    retention: { run: tenantId => retention.rollover(tenantId) },
    authenticator: new ConsoleLandscapeOperationsAuthenticator(
      app.landscape,
      new SignedConsoleNativeAuthorizer({
        clock: consoleClock,
        keyId: consoleKeys.keyId,
        issuer: security.managementIssuer,
        audience: security.managementAudience,
        verifyingKey: consoleKeys.publicKey,
      }),
    ),
    clock,
    identifiers,
    supervisor,
  });

  const operations = config('providerOperations');
  const appleSeam = seams.appleBackfill;
  const appleOptions: AppleBackfillOptions = {
    operationKey: operations.apple.operationKey,
    landscape: app.landscape,
    preferredHostLandscape: operations.apple.preferredHostLandscape,
    intakePath: operations.apple.intakePath,
    leaseDurationMs: operations.apple.leaseDurationMs,
    ...(operations.apple.pageSize === undefined ? {} : { pageSize: operations.apple.pageSize }),
  };
  const appleBackfill = operations.apple.enabled
    ? new AppleServerApiBackfillRunner(
        appleSeam?.history ??
          createAppleAppStoreNotificationHistoryClient(providerSecrets, clock, operations.apple.jwt, {
            ...operations.apple.history,
            fetch: baseFetch,
          }),
        new PostgresAppleBackfillStateStore(sql),
        // Backfill must acknowledge persisted events, not just persist them, so
        // their delivery jobs enter the ready queue. Adapt the intake engine's
        // provider-acknowledgement seam onto the backfill intake port.
        {
          intake: request => intake.intake(request),
          acknowledge: eventId => intake.acknowledgeProviderResponse(eventId),
        },
        clock,
        identifiers,
        appleOptions,
      )
    : undefined;

  const googleSeam = seams.googleRtdn;
  const googleClient = operations.google.enabled
    ? (googleSeam?.client ??
      new FetchGooglePubSubAdministrationClient(
        googleSeam?.accessTokens ??
          createGoogleServiceAccountOAuthAccessTokenReader(providerSecrets, clock, {
            ...operations.google.oauth,
            fetch: baseFetch,
          }),
        { fetch: baseFetch, ...googleSeam?.restOptions },
      ))
    : undefined;
  const googleOptions: GooglePlayRtdnReconcilerOptions = {
    subscriptionName: operations.google.subscriptionName,
    deadLetterTopic: operations.google.deadLetterTopic,
    deadLetterMaxDeliveryAttempts: operations.google.deadLetterMaxDeliveryAttempts,
    registeredPushUrl: operations.google.registeredPushUrl,
    oidcServiceAccountEmail: operations.google.oidcServiceAccountEmail,
    ...(operations.google.oidcAudience === undefined ? {} : { oidcAudience: operations.google.oidcAudience }),
  };
  const googleReconciler =
    operations.google.enabled && googleClient !== undefined
      ? new GooglePlayRtdnSubscriptionReconciler(googleClient, googleOptions)
      : undefined;

  let startupDone = false;
  let shuttingDown = false;
  let materialized = false;
  let managementState: MercuryDependencyState = 'degraded';
  let server: MercuryServerHandle | undefined;
  let reconcileTimer: ReturnType<typeof setInterval> | undefined;
  let reconciling = false;
  const operationTimers: ReturnType<typeof setInterval>[] = [];
  const operationLifetime = new AbortController();
  // Every reconcile and provider-operation tick registers here so shutdown can
  // await in-flight work — not just clear its timers — before tearing down
  // Redis/Postgres/telemetry.
  const inFlightOperations = new Set<Promise<void>>();
  const trackInFlight = (start: () => Promise<void>): void => {
    const settled = start().finally(() => {
      inFlightOperations.delete(settled);
    });
    inFlightOperations.add(settled);
  };

  /**
   * Intake is refused with a retryable problem until every security input has
   * been preflighted, and again once shutdown begins. A missing or malformed
   * secret must never surface to a provider as an authentication failure.
   */
  const gatedIntake = async (request: Request): Promise<Response> => {
    if (startupDone) {
      return intakeHandler(request);
    }
    const path = new URL(request.url).pathname;
    const problem = intakeProblems.fromFailure(
      { code: 'config-unavailable', message: 'Mercury intake is not accepting traffic yet' },
      path,
    );
    return new Response(JSON.stringify(problem), {
      status: problem.status,
      headers: { 'content-type': 'application/problem+json', 'retry-after': '1' },
    });
  };

  const readiness = async (): Promise<MercuryReadinessReport> => {
    let redisState: MercuryDependencyState = 'degraded';
    try {
      redisState = (await redis.ping()) === 'PONG' ? 'ok' : 'degraded';
    } catch {
      redisState = 'degraded';
    }
    const generation = await activeGeneration(runtimeConfig);
    const dependencies: Record<string, MercuryDependencyState> = {
      config: generation === null ? 'degraded' : 'ok',
      management: managementState,
      redis: redisState,
      secrets: materialized ? 'ok' : 'degraded',
      supervisor: supervisor.running ? 'ok' : 'degraded',
    };
    return {
      ready: !shuttingDown && redisState === 'ok' && generation !== null && materialized && supervisor.running,
      dependencies,
    };
  };

  const router = createMercuryHttpApplication({
    // `/config/compile` is bound to the trusted local topology only; the API
    // clones it and rejects any binding that is not exactly this landscape.
    management: createManagementApi(management, {
      compilation: { compiler, localLandscape: app.landscape, topology },
    }) as unknown as Hono,
    console: consoleApp,
    landscape: landscapeApi,
    intake: gatedIntake,
    startupComplete: () => startupDone,
    readiness,
    metrics: async () => ({
      body: await registry.metrics(),
      contentType: registry.contentType,
    }),
  });

  const preflightCompiledSecrets = async (): Promise<void> => {
    const generation = await activeGeneration(runtimeConfig);
    if (generation === null) {
      return;
    }
    const verificationRefs = new Set<string>();
    const signingRefs = new Set<string>();
    for (const tenant of generation.tenants) {
      for (const route of tenant.routes) {
        if (route.verificationSecretRef !== undefined) {
          verificationRefs.add(route.verificationSecretRef);
        }
        for (const endpoint of route.endpoints) {
          signingRefs.add(endpoint.signingSecretRef);
        }
      }
    }
    for (const reference of verificationRefs) {
      const configuration = await providerConfigurations.read(reference).catch(() => undefined);
      if (configuration === undefined) {
        throw new Error('a compiled provider verification configuration is unavailable');
      }
    }
    for (const reference of signingRefs) {
      const material = await deliverySecrets.read(reference);
      if (await material.isErr()) {
        throw new Error('a compiled endpoint signing secret is unavailable');
      }
      (await material.unwrap()).fill(0);
    }
  };

  // Callable H2 preflight over a resolved generation. The management compiler
  // (peer-owned) awaits `preflightProviderReadiness` immediately before its CAS
  // to refuse activating a generation with an unsupported/misconfigured provider
  // or unreadable signing secret; the same check runs here at reconcile as
  // defense in depth against an already-active bad generation.
  const preflightActiveGeneration = async (): Promise<boolean> => {
    const generation = await activeGeneration(runtimeConfig);
    if (generation === null) {
      return true;
    }
    try {
      await preflightProviderReadiness(projectGenerationRoutes(generation), {
        providerConfigurations,
        deliverySecrets,
      });
      return true;
    } catch {
      return false;
    }
  };

  const materialize = async (): Promise<void> => {
    try {
      await compiler.compileAndPublish(topology);
      // Defense in depth: never advertise management healthy while the active
      // generation fails provider readiness.
      managementState = (await preflightActiveGeneration()) ? 'ok' : 'degraded';
    } catch {
      // Neon degradation must never invalidate an already-materialized
      // generation; intake keeps serving the active local configuration. With
      // nothing materialized there is no safe configuration to serve, so boot
      // fails closed instead of living forever unready.
      managementState = 'degraded';
      await telemetry
        .record({ name: 'config.materialize.failure', attributes: { landscape: app.landscape } })
        .catch(() => undefined);
      if ((await activeGeneration(runtimeConfig)) === null) {
        throw new Error('no materialized runtime configuration is available');
      }
    }
  };

  const reconcile = async (): Promise<void> => {
    if (reconciling || shuttingDown) {
      return;
    }
    reconciling = true;
    try {
      const lease = await redis.set(RECONCILE_LEASE_KEY, identifiers.create(), 'PX', reconcileIntervalMs, 'NX');
      if (lease !== 'OK') {
        return;
      }
      await materialize();
    } catch {
      managementState = 'degraded';
    } finally {
      reconciling = false;
    }
  };

  /**
   * Provider operations run outside the two-loop runtime supervisor because it
   * only names `delivery` and `retention`. Each tick is non-overlapping,
   * cancellable, and never allowed to fault the process.
   */
  const startOperationLoop = (name: string, intervalMs: number, run: (signal: AbortSignal) => Promise<void>): void => {
    let running = false;
    const tick = async (): Promise<void> => {
      if (running || shuttingDown || operationLifetime.signal.aborted) {
        return;
      }
      running = true;
      try {
        await run(operationLifetime.signal);
      } catch {
        await telemetry
          .record({
            name: 'runtime.job.failure',
            attributes: { code: 'operation-failed', job: name, landscape: app.landscape },
          })
          .catch(() => undefined);
      } finally {
        running = false;
      }
    };
    operationTimers.push(setInterval(() => trackInFlight(tick), intervalMs));
  };

  const start = async (): Promise<void> => {
    // Nothing is bound until the local generation exists and every compiled
    // security input has been proven readable.
    supervisor.start();
    await materialize();
    await preflightCompiledSecrets();
    materialized = true;
    server = (seams.serve ?? (options => Bun.serve(options)))({
      hostname: app.bind,
      port: app.port,
      // Reject oversized bodies at the server boundary before route lookup or
      // materialization; the bounded intake reader enforces the same limit.
      maxRequestBodySize: MERCURY_MAX_REQUEST_BODY_BYTES,
      fetch: async request => router.fetch(request),
    });
    reconcileTimer = setInterval(() => trackInFlight(reconcile), reconcileIntervalMs);
    if (appleBackfill !== undefined) {
      startOperationLoop('provider.apple.backfill', operations.apple.intervalMs, async signal => {
        const cycle = await appleBackfill.runCycle(signal);
        // Publish the durable missed-cycle count after every cycle so the
        // bounded gauge tracks both escalation and the reset a successful cycle
        // performs. Preferred-host exclusion/non-host cycles carry no state and
        // leave the last published value untouched.
        const state = (await cycle.isOk()) ? (await cycle.unwrap()).state : (await cycle.unwrapErr()).state;
        if (state !== undefined) {
          await telemetry
            .record({
              name: 'provider.apple.backfill',
              attributes: {
                landscape: app.landscape,
                operation: operations.apple.operationKey,
                alert: state.alert,
              },
              value: state.consecutiveMissedCycles,
            })
            .catch(() => undefined);
        }
        if (await cycle.isErr()) {
          throw new Error((await cycle.unwrapErr()).code);
        }
      });
    }
    if (googleReconciler !== undefined) {
      startOperationLoop('provider.google.rtdn', operations.google.intervalMs, async signal => {
        const report = await googleReconciler.reconcile(signal);
        if (await report.isErr()) {
          throw new Error((await report.unwrapErr()).code);
        }
      });
    }
    startupDone = true;
  };

  const shutdown = async (): Promise<void> => {
    if (shuttingDown) {
      return;
    }
    shuttingDown = true;
    startupDone = false;
    if (reconcileTimer !== undefined) {
      clearInterval(reconcileTimer);
      reconcileTimer = undefined;
    }
    for (const timer of operationTimers.splice(0)) {
      clearInterval(timer);
    }
    operationLifetime.abort();
    // Stop admitting new connections, then drain in-flight reconcile and
    // provider-operation work AND the delivery/retention supervisor within a
    // single shared grace budget before any dependency is torn down.
    await Promise.resolve(server?.stop(false)).catch(() => undefined);
    const deadlineMs = clock.nowMs() + app.shutdownGraceMs;
    const remaining = (): number => Math.max(0, deadlineMs - clock.nowMs());
    const operationsDrained = await withTimeout(
      Promise.allSettled([...inFlightOperations]).then(() => undefined),
      remaining(),
    );
    supervisor.stop();
    const drained = await withTimeout(supervisor.drain(), remaining());
    if (!operationsDrained || !drained) {
      await telemetry.record({
        name: 'runtime.shutdown.timeout',
        attributes: { landscape: app.landscape },
      });
    }
    await Promise.resolve(server?.stop(true)).catch(() => undefined);
    server = undefined;
    await Promise.resolve(redis.quit()).catch(() => undefined);
    await Promise.resolve(sql.end({ timeout: 5 })).catch(() => undefined);
    await otel.flush().catch(() => undefined);
    await otel.shutdown().catch(() => undefined);
  };

  return {
    config,
    registry,
    supervisor,
    router,
    fetch: async request => router.fetch(request),
    startupComplete: () => startupDone,
    readiness,
    start,
    shutdown,
  };
}

/**
 * Applies pending migrations and mints the default internal management
 * credential from the mounted bootstrap token. The token is never echoed.
 */
export async function runMercuryDbInit(
  config: MercuryConfig,
  seams: MercuryCompositionSeams & { readonly migrationsDirectory?: string } = {},
): Promise<MercuryDbInitResult> {
  const storage = config('storage');
  const security = config('security');
  const references = secretReferencesFrom(seams.secretReferences);
  const createSecretReader =
    seams.createSecretReader ?? ((root, mapping) => new MountedSecretReader({ root, mapping }));
  const platformSecrets = createSecretReader(security.endpointSecretRoot, {
    [references.managementBootstrapToken]: security.managementBootstrapTokenFile,
  });

  const bootstrapToken = await readRequiredSecretText(
    platformSecrets,
    references.managementBootstrapToken,
    'management bootstrap token',
  );
  const sql = (seams.createSql ?? (url => postgres(url, { max: 2 })))(storage.postgresUrl);
  try {
    const migrations = await runMercuryMigrations(sql, seams.migrationsDirectory);
    const service = new ManagementService(new PostgresManagementRepository(sql));
    const provisioned = await service.provisionDefaultInternalAccount(bootstrapToken);
    return {
      migrations: migrations.map(migration => migration.name),
      accountId: provisioned.account.id,
      credentialIssued: provisioned.issued !== undefined,
    };
  } finally {
    await Promise.resolve(sql.end({ timeout: 5 })).catch(() => undefined);
  }
}
