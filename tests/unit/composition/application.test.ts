import { beforeAll, describe, expect, test } from 'bun:test';
import { Err, Ok } from '@atomicloud/diene.result';
import type Redis from 'ioredis';
import {
  createCertificateReadinessProbe,
  createMercuryApplication,
  LocalCircuitCommander,
  LocalReplayDispatcher,
  localLandscapeTopology,
  ManagementReplayAuditor,
  type MercuryApplication,
  type MercuryCompositionSeams,
  type MercuryServerHandle,
  preflightProviderReadiness,
} from '../../../src/composition/application.ts';
import type { MercuryConfig } from '../../../src/composition/config.ts';
import type { DeliveryEngine } from '../../../src/delivery/index.ts';
import type { Clock, IdentifierFactory, LandscapeRuntimeConfig, SecretReader } from '../../../src/domain/index.ts';
import type { PostgresManagementRepository } from '../../../src/management/index.ts';
import { encodeRuntimeConfig } from '../../../src/storage/codec.ts';

const ENDPOINT_SECRET_ROOT = '/var/run/secrets/mercury';
const PROVIDER_SECRET_ROOT = '/var/run/secrets/mercury/providers';

interface KeyMaterial {
  readonly privateKey: Uint8Array;
  readonly publicKey: Uint8Array;
  readonly foreignPublicKey: Uint8Array;
}

let keys: KeyMaterial;

const exportPair = async (): Promise<{ pkcs8: Uint8Array; spki: Uint8Array }> => {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  return {
    pkcs8: new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey)),
    spki: new Uint8Array(await crypto.subtle.exportKey('spki', pair.publicKey)),
  };
};

beforeAll(async () => {
  const primary = await exportPair();
  const secondary = await exportPair();
  keys = {
    privateKey: primary.pkcs8,
    publicKey: primary.spki,
    foreignPublicKey: secondary.spki,
  };
});

const configBlocks = (
  overrides: Readonly<Record<string, Readonly<Record<string, unknown>>>> = {},
): Record<string, unknown> => ({
  app: {
    landscape: 'base',
    platform: 'mercury',
    service: 'webhook',
    module: 'hooks',
    version: '1.0.0',
    bind: '127.0.0.1',
    port: 8080,
    publicOrigin: 'https://hooks.example.test',
    previewDeliveryVisible: false,
    shutdownGraceMs: 15_000,
    ...overrides.app,
  },
  storage: {
    redisUrl: 'redis://127.0.0.1:6379',
    postgresUrl: 'postgres://mercury:mercury@127.0.0.1:5432/mercury',
    archiveEndpoint: 'http://127.0.0.1:9000',
    archiveBucket: 'mercury-webhook-archive',
    archiveRegion: 'us-east-1',
    ...overrides.storage,
  },
  security: {
    consoleSessionSecretFile: `${ENDPOINT_SECRET_ROOT}/console-session`,
    managementBootstrapTokenFile: `${ENDPOINT_SECRET_ROOT}/management-bootstrap-token`,
    providerSecretRoot: PROVIDER_SECRET_ROOT,
    endpointSecretRoot: ENDPOINT_SECRET_ROOT,
    archiveAccessKeyIdFile: `${ENDPOINT_SECRET_ROOT}/archive-access-key-id`,
    archiveSecretAccessKeyFile: `${ENDPOINT_SECRET_ROOT}/archive-secret-access-key`,
    consoleAuthorizationPrivateKeyFile: `${ENDPOINT_SECRET_ROOT}/console-authorization-private-key`,
    consoleAuthorizationPublicKeyFile: `${ENDPOINT_SECRET_ROOT}/console-authorization-public-key`,
    managementIssuer: 'mercury',
    managementAudience: 'mercury-management',
    ...overrides.security,
  },
  topology: {
    services: {
      'billing/api': {
        module: 'api',
        localLandscapes: ['base'],
        canonicalVlandscape: 'prod',
      },
    },
    ...overrides.topology,
  },
  providerOperations: {
    apple: {
      enabled: false,
      operationKey: 'apple-backfill',
      preferredHostLandscape: 'base',
      intakePath: '/t/acme/apple',
      leaseDurationMs: 60_000,
      intervalMs: 60_000,
      jwt: {
        issuerId: 'issuer-1',
        keyId: 'key-1',
        bundleId: 'cloud.atomi.mercury',
        signingKeySecretRef: 'apple-app-store-history.p8',
      },
      history: {
        environment: 'Sandbox',
        request: { startDateMs: 1_700_000_000_000, endDateMs: 1_700_003_600_000 },
      },
    },
    google: {
      enabled: false,
      subscriptionName: 'projects/p/subscriptions/s',
      deadLetterTopic: 'projects/p/topics/dead',
      deadLetterMaxDeliveryAttempts: 5,
      registeredPushUrl: 'https://hooks.example.test/t/acme/google-play',
      oidcServiceAccountEmail: 'rtdn@example.iam.gserviceaccount.com',
      oauth: {
        credentialSecretRef: 'google-pubsub-service-account.json',
        expectedServiceAccountEmail: 'rtdn@example.iam.gserviceaccount.com',
      },
      intervalMs: 60_000,
    },
    ...overrides.providerOperations,
  },
  otel: {},
});

const testConfig = (overrides: Readonly<Record<string, Readonly<Record<string, unknown>>>> = {}): MercuryConfig => {
  const blocks = configBlocks(overrides);
  const accessor = (key: string): unknown => blocks[key];
  return Object.assign(accessor, {
    get: accessor,
    all: () => blocks,
  }) as unknown as MercuryConfig;
};

class FakeSecretReader implements SecretReader {
  constructor(readonly entries: Map<string, Uint8Array>) {}

  async read(secretRef: string): ReturnType<SecretReader['read']> {
    const material = this.entries.get(secretRef);
    return material === undefined
      ? (await import('@atomicloud/diene.result')).Err({
          code: 'not-found' as const,
          message: 'secret reference was not found',
        })
      : Ok(material.slice());
  }
}

const utf8 = (value: string): Uint8Array => new TextEncoder().encode(value);

interface SecretOverrides {
  readonly omit?: readonly string[];
  readonly publicKey?: Uint8Array;
  readonly consoleSessionSecret?: Uint8Array;
}

// Only tenant-registered endpoint pointers live beneath the endpoint mount.
// The real-stack proof registers them as `/coordinate`-style vault pointers.
const endpointEntries = new Map<string, Uint8Array>([['coordinate', utf8('d'.repeat(48))]]);
const providerEntries = new Map<string, Uint8Array>([
  ['stripe.json', utf8('{"secrets":["hmac"],"toleranceSeconds":300}')],
]);

const compiledGeneration = (signingSecretRef: string): LandscapeRuntimeConfig => ({
  generation: 9,
  landscape: 'base',
  compiledAtMs: 1_700_000_000_000,
  sourceRevision: 'hash-9',
  tenants: [
    {
      id: 'tenant-1',
      slug: 'acme',
      registeredDomains: [],
      intakeRps: 10,
      intakeBurst: 20,
      retryWindowMs: 60_000,
      routes: [
        {
          id: 'route-1',
          path: '/stripe',
          canonicalPath: '/t/acme/stripe',
          provider: 'stripe',
          registeredUrl: 'https://hooks.example.test/t/acme/stripe',
          verificationSecretRef: '/stripe.json',
          endpoints: [
            {
              id: 'endpoint-1',
              address: 'https://sink.example.test/hook',
              addressKind: 'external',
              canonicalUrl: 'https://sink.example.test/hook',
              signingSecretRef,
            },
          ],
        },
      ],
    },
  ],
});

const secretEntries = (overrides: SecretOverrides = {}): Map<string, Uint8Array> => {
  const entries = new Map<string, Uint8Array>([
    ['console-session', overrides.consoleSessionSecret ?? utf8('a'.repeat(48))],
    ['management-bootstrap-token', utf8('bootstrap-token-value')],
    ['console-authorization-private-key', keys.privateKey],
    ['console-authorization-public-key', overrides.publicKey ?? keys.publicKey],
    ['archive-access-key-id', utf8('archive-key-id')],
    ['archive-secret-access-key', utf8('archive-secret')],
    ['mercury/endpoints/acme', utf8('c'.repeat(48))],
  ]);
  for (const omitted of overrides.omit ?? []) {
    entries.delete(omitted);
  }
  return entries;
};

interface RedisScript {
  readonly generation?: LandscapeRuntimeConfig;
  readonly ping?: string;
  readonly lease?: 'OK' | null;
}

interface FakeRedis {
  readonly client: Redis;
  readonly quits: number[];
}

const fakeRedis = (script: RedisScript = {}): FakeRedis => {
  const quits: number[] = [];
  const known: Record<string, (...args: unknown[]) => Promise<unknown>> = {
    ping: async () => script.ping ?? 'PONG',
    get: async (...args: unknown[]) => {
      const key = String(args[0]);
      if (script.generation === undefined) {
        return null;
      }
      if (key === 'cfg:gen') {
        return String(script.generation.generation);
      }
      if (key === `cfg:${script.generation.generation}:landscape`) {
        return encodeRuntimeConfig(script.generation);
      }
      return null;
    },
    set: async () => script.lease ?? 'OK',
    quit: async () => {
      quits.push(Date.now());
      return 'OK';
    },
  };
  const client = new Proxy(
    {},
    {
      get: (_target, property) => {
        const name = String(property);
        return known[name] ?? (async () => null);
      },
    },
  ) as unknown as Redis;
  return { client, quits };
};

interface FakeSql {
  // biome-ignore lint/suspicious/noExplicitAny: the postgres tag accepts arbitrary bound values
  (strings: TemplateStringsArray, ...values: readonly any[]): Promise<never>;
  end(options?: unknown): Promise<void>;
}

const fakeSql = (ended: string[]): FakeSql => {
  const tag = (async () => {
    throw new Error('management database is unavailable');
  }) as unknown as FakeSql;
  tag.end = async () => {
    ended.push('end');
  };
  return tag;
};

class FakeServer implements MercuryServerHandle {
  readonly stops: boolean[] = [];

  stop(closeActiveConnections?: boolean): unknown {
    this.stops.push(closeActiveConnections === true);
    return undefined;
  }
}

const fakeOtel = (record: string[]) =>
  ({
    logger: {
      error: () => undefined,
      info: () => undefined,
      warn: () => undefined,
    },
    traceEmitter: { emit: () => Ok(undefined), flush: () => Ok(undefined) },
    flush: async () => {
      record.push('flush');
    },
    shutdown: async () => {
      record.push('shutdown');
    },
    // biome-ignore lint/suspicious/noExplicitAny: only the fields Mercury consumes are modelled
  }) as any;

interface Harness {
  readonly seams: MercuryCompositionSeams;
  readonly server: FakeServer;
  readonly redis: FakeRedis;
  readonly ended: string[];
  readonly otelCalls: string[];
}

const harness = (options: { readonly secrets?: SecretOverrides; readonly redis?: RedisScript } = {}): Harness => {
  const server = new FakeServer();
  const redis = fakeRedis(options.redis);
  const ended: string[] = [];
  const otelCalls: string[] = [];
  const entries = secretEntries(options.secrets);
  const seams: MercuryCompositionSeams = {
    createRedis: () => redis.client,
    createSql: () => fakeSql(ended) as never,
    createTelemetry: () => fakeOtel(otelCalls),
    createSecretReader: (root, mapping) =>
      new FakeSecretReader(
        root === PROVIDER_SECRET_ROOT ? providerEntries : Object.keys(mapping).length > 0 ? entries : endpointEntries,
      ),
    createArchiveStore: () => ({ put: async () => Ok(undefined) as never }),
    serve: () => server,
    fetch: Object.assign(async () => new Response(null, { status: 200 }), {
      preconnect: () => undefined,
    }) as unknown as typeof globalThis.fetch,
    retentionIntervalMs: 3_600_000,
    deliveryIntervalMs: 3_600_000,
    reconcileIntervalMs: 3_600_000,
  };
  return { seams, server, redis, ended, otelCalls };
};

const activeConfig: LandscapeRuntimeConfig = {
  generation: 7,
  landscape: 'base',
  compiledAtMs: 1_700_000_000_000,
  sourceRevision: 'hash-7',
  tenants: [],
};

describe('Mercury trusted topology', () => {
  test('pins the local landscape and copies only configured services', () => {
    const config = testConfig();
    const topology = localLandscapeTopology(config);

    expect(topology.landscapes).toEqual(['base']);
    expect(Object.keys(topology.services)).toEqual(['billing/api']);
    expect(topology.services).not.toBe(config('topology').services);
  });

  test('refuses an injected topology that is not exactly the local landscape', async () => {
    const { seams } = harness();

    await expect(
      createMercuryApplication(testConfig(), {
        ...seams,
        topology: { landscapes: ['base', 'other'], services: {} },
      }),
    ).rejects.toThrow('compiles only its own landscape topology');
  });
});

describe('Mercury composition fails closed on security inputs', () => {
  test('rejects a missing console session secret', async () => {
    const { seams } = harness({ secrets: { omit: ['console-session'] } });

    await expect(createMercuryApplication(testConfig(), seams)).rejects.toThrow(
      'console session secret is unavailable',
    );
  });

  test('rejects a console session secret below the minimum key length', async () => {
    const { seams } = harness({ secrets: { consoleSessionSecret: utf8('short') } });

    await expect(createMercuryApplication(testConfig(), seams)).rejects.toThrow('console session secret is invalid');
  });

  test('rejects a mismatched console authorization key pair', async () => {
    const { seams } = harness({ secrets: { publicKey: keys.foreignPublicKey } });

    await expect(createMercuryApplication(testConfig(), seams)).rejects.toThrow(
      'console authorization key pair does not match',
    );
  });

  test('rejects a missing archive credential', async () => {
    const { seams } = harness({ secrets: { omit: ['archive-secret-access-key'] } });

    await expect(createMercuryApplication(testConfig(), seams)).rejects.toThrow(
      'archive secret access key is unavailable',
    );
  });

  test('releases telemetry, redis, and postgres when a security input is rejected', async () => {
    const bench = harness({ secrets: { publicKey: keys.foreignPublicKey } });

    await expect(createMercuryApplication(testConfig(), bench.seams)).rejects.toThrow();

    expect(bench.otelCalls).toEqual(['flush', 'shutdown']);
    expect(bench.redis.quits.length).toBe(0);
    expect(bench.ended).toEqual([]);
  });

  test('releases every earlier resource when a later dependency rejects', async () => {
    const bench = harness({ redis: { generation: activeConfig } });

    await expect(
      createMercuryApplication(testConfig({ app: { publicOrigin: 'https://console/path' } }), bench.seams),
    ).rejects.toThrow();

    expect(bench.otelCalls).toEqual(['flush', 'shutdown']);
    expect(bench.redis.quits.length).toBe(1);
    expect(bench.ended).toEqual(['end']);
  });

  test('preflights compiled provider and endpoint pointers from their own mounts', async () => {
    const bench = harness({ redis: { generation: compiledGeneration('/coordinate') } });
    const application = await createMercuryApplication(testConfig(), bench.seams);

    await application.start();
    expect(application.startupComplete()).toBe(true);

    await application.shutdown();
  });

  test('never resolves a tenant endpoint pointer against the platform key mapping', async () => {
    // `/console-session` is a logical platform key name. A tenant-registered
    // pointer must resolve only beneath the endpoint mount, where it is absent,
    // so startup fails closed rather than signing with platform key material.
    const bench = harness({ redis: { generation: compiledGeneration('/console-session') } });
    const application = await createMercuryApplication(testConfig(), bench.seams);

    await expect(application.start()).rejects.toThrow('a compiled endpoint signing secret is unavailable');
    expect(bench.server.stops).toEqual([]);
    expect(application.startupComplete()).toBe(false);

    await application.shutdown();
  });

  test('composes the enabled provider operations from their configured refs', async () => {
    const bench = harness({ redis: { generation: compiledGeneration('/coordinate') } });
    // The real-stack proof configures these as plain relative names, not vault
    // pointers, so the adapters must read the root-confined provider mount.
    const enabled = testConfig({
      providerOperations: {
        apple: {
          ...(configBlocks().providerOperations as { apple: Record<string, unknown> }).apple,
          enabled: true,
          jwt: {
            issuerId: '00000000-0000-4000-8000-000000000001',
            keyId: 'SITKEY0001',
            bundleId: 'cloud.atomi.mercury.sit',
            signingKeySecretRef: 'apple-app-store-history.p8',
          },
          intervalMs: 3_600_000,
        },
        google: {
          ...(configBlocks().providerOperations as { google: Record<string, unknown> }).google,
          enabled: true,
          oauth: {
            credentialSecretRef: 'google-pubsub-service-account.json',
            expectedServiceAccountEmail: 'rtdn@example.iam.gserviceaccount.com',
          },
          intervalMs: 3_600_000,
        },
      },
    });

    const application = await createMercuryApplication(enabled, bench.seams);
    await application.start();
    expect(application.startupComplete()).toBe(true);

    await application.shutdown();
  });

  test('rejects a delivery timeout that outlives the shutdown grace period', async () => {
    const { seams } = harness();

    await expect(
      createMercuryApplication(testConfig({ app: { shutdownGraceMs: 2_000 } }), {
        ...seams,
        deliveryTimeoutMs: 9_000,
      }),
    ).rejects.toThrow('delivery timeout must not exceed');
  });
});

describe('Mercury application lifecycle', () => {
  const started = async (
    options: { readonly redis?: RedisScript } = {},
  ): Promise<{ readonly application: MercuryApplication; readonly bench: Harness }> => {
    const bench = harness(options);
    const application = await createMercuryApplication(testConfig(), bench.seams);
    await application.start();
    return { application, bench };
  };

  test('binds the server, runs the supervisor, and completes startup', async () => {
    const { application, bench } = await started({ redis: { generation: activeConfig } });

    expect(application.startupComplete()).toBe(true);
    expect(application.supervisor.running).toBe(true);
    expect(bench.server.stops).toEqual([]);

    await application.shutdown();
  });

  test('serves liveness before startup completes and reports startup progress', async () => {
    const bench = harness({ redis: { generation: activeConfig } });
    const application = await createMercuryApplication(testConfig(), bench.seams);

    expect((await application.fetch(new Request('http://local/health/live'))).status).toBe(200);
    expect((await application.fetch(new Request('http://local/health/startup'))).status).toBe(503);
    expect(bench.server.stops).toEqual([]);

    await application.start();
    expect((await application.fetch(new Request('http://local/health/startup'))).status).toBe(200);
    await application.shutdown();
  });

  test('refuses tenant intake with a retryable problem until startup completes', async () => {
    const bench = harness({ redis: { generation: activeConfig } });
    const application = await createMercuryApplication(testConfig(), bench.seams);

    const refused = await application.fetch(new Request('http://local/t/acme/stripe', { method: 'POST', body: '{}' }));
    expect(refused.status).toBe(503);
    expect(refused.headers.get('content-type')).toBe('application/problem+json');
    expect(refused.headers.get('retry-after')).toBe('1');

    await application.start();
    await application.shutdown();

    const afterShutdown = await application.fetch(
      new Request('http://local/t/acme/stripe', { method: 'POST', body: '{}' }),
    );
    expect(afterShutdown.status).toBe(503);
  });

  test('is ready only when the local generation, redis, secrets, and supervisor agree', async () => {
    const { application, bench } = await started({ redis: { generation: activeConfig } });

    const ready = await application.readiness();
    expect(ready.ready).toBe(true);
    expect(ready.dependencies.config).toBe('ok');
    expect(ready.dependencies.redis).toBe('ok');
    expect(ready.dependencies.supervisor).toBe('ok');
    expect(bench.ended).toEqual([]);

    await application.shutdown();
  });

  test('degrades management without rejecting an already-materialized generation', async () => {
    const { application } = await started({ redis: { generation: activeConfig } });

    const report = await application.readiness();
    expect(report.dependencies.management).toBe('degraded');
    expect(report.ready).toBe(true);

    await application.shutdown();
  });

  test('fails closed on first boot when nothing has been materialized', async () => {
    const bench = harness();
    const application = await createMercuryApplication(testConfig(), bench.seams);

    // The stub management database always rejects, so the first compile cannot
    // publish and there is no previously active local generation to serve.
    await expect(application.start()).rejects.toThrow('no materialized runtime configuration is available');
    expect(bench.server.stops).toEqual([]);
    expect(application.startupComplete()).toBe(false);
    expect((await application.readiness()).ready).toBe(false);

    await application.shutdown();
  });

  test('is not ready once redis stops answering', async () => {
    const { application } = await started({
      redis: { generation: activeConfig, ping: 'NOPE' },
    });

    const report = await application.readiness();
    expect(report.ready).toBe(false);
    expect(report.dependencies.redis).toBe('degraded');

    await application.shutdown();
  });

  test('exposes the same prometheus registry the runtime telemetry writes to', async () => {
    const { application } = await started({ redis: { generation: activeConfig } });

    const response = await application.fetch(new Request('http://local/metrics'));
    expect(response.headers.get('content-type')).toContain('text/plain');
    expect(await response.text()).toContain('mercury_intake_total');

    await application.shutdown();
  });

  test('reserves internal surfaces and leaves the intake catch-all last', async () => {
    const { application } = await started({ redis: { generation: activeConfig } });

    expect((await application.fetch(new Request('http://local/management/v1/health'))).status).toBe(401);
    const intake = await application.fetch(new Request('http://local/t/acme/stripe', { method: 'POST', body: '{}' }));
    expect(intake.headers.get('content-type')).toBe('application/problem+json');

    await application.shutdown();
  });

  test('shuts down bounded: stops traffic, drains, and closes every resource once', async () => {
    const { application, bench } = await started({ redis: { generation: activeConfig } });

    await application.shutdown();

    expect(bench.server.stops).toEqual([false, true]);
    expect(application.supervisor.running).toBe(false);
    expect(bench.redis.quits.length).toBe(1);
    expect(bench.ended).toEqual(['end']);
    expect(bench.otelCalls).toEqual(['flush', 'shutdown']);
    expect((await application.readiness()).ready).toBe(false);
    expect(application.startupComplete()).toBe(false);

    await application.shutdown();
    expect(bench.redis.quits.length).toBe(1);
  });
});

describe('Landscape-local management dispatch', () => {
  const engine = (calls: string[], fail = false): DeliveryEngine =>
    ({
      flow: {
        landscape: 'base',
      },
      probeEndpoint: async (tenantId: string, endpointId: string) => {
        calls.push(`probe:${tenantId}:${endpointId}`);
        return fail
          ? (await import('@atomicloud/diene.result')).Err({
              code: 'storage-unavailable',
              message: 'down',
            })
          : Ok(true);
      },
      replayEvent: async (eventId: string) => {
        calls.push(`event:${eventId}`);
        return fail
          ? (await import('@atomicloud/diene.result')).Err({
              code: 'storage-unavailable',
              message: 'down',
            })
          : Ok([]);
      },
      replayEndpointFailures: async (tenantId: string, endpointId: string) => {
        calls.push(`endpoint:${tenantId}:${endpointId}`);
        return Ok([]);
      },
      manualClose: async (tenantId: string, endpointId: string) => {
        calls.push(`close:${tenantId}:${endpointId}`);
        return Ok(undefined);
      },
      // biome-ignore lint/suspicious/noExplicitAny: only the dispatched surface is modelled
    }) as any;

  test('dispatches event and endpoint replay against the local landscape', async () => {
    const calls: string[] = [];
    const dispatcher = new LocalReplayDispatcher('base', engine(calls));

    await dispatcher.dispatch({
      landscape: 'base',
      tenantId: 'tenant-1',
      scope: { kind: 'event', eventId: 'event-1' },
      commandId: 'command-1',
    });
    await dispatcher.dispatch({
      landscape: 'base',
      tenantId: 'tenant-1',
      scope: { kind: 'endpoint', endpointId: 'endpoint-1' },
      commandId: 'command-2',
    });

    expect(calls).toEqual(['event:event-1', 'endpoint:tenant-1:endpoint-1']);
  });

  test('refuses to dispatch into another landscape', async () => {
    const dispatcher = new LocalReplayDispatcher('base', engine([]));

    await expect(
      dispatcher.dispatch({
        landscape: 'other',
        tenantId: 'tenant-1',
        scope: { kind: 'event', eventId: 'event-1' },
        commandId: 'command-1',
      }),
    ).rejects.toThrow('confined to the local landscape');
  });

  test('surfaces a failed replay instead of silently succeeding', async () => {
    const dispatcher = new LocalReplayDispatcher('base', engine([], true));

    await expect(
      dispatcher.dispatch({
        landscape: 'base',
        tenantId: 'tenant-1',
        scope: { kind: 'event', eventId: 'event-1' },
        commandId: 'command-1',
      }),
    ).rejects.toThrow('replay dispatch failed');
  });

  test('re-enables and probes local circuits', async () => {
    const calls: string[] = [];
    const commander = new LocalCircuitCommander('base', engine(calls));

    await commander.reenable({ landscape: 'base', tenantId: 'tenant-1', endpointId: 'endpoint-1' });
    expect(calls).toEqual(['close:tenant-1:endpoint-1']);
    expect(await commander.probe({ landscape: 'base', tenantId: 'tenant-1', endpointId: 'endpoint-1' })).toBe(true);
    expect(calls).toEqual(['close:tenant-1:endpoint-1', 'probe:tenant-1:endpoint-1']);
    await expect(
      new LocalCircuitCommander('base', engine([], true)).probe({
        landscape: 'base',
        tenantId: 'tenant-1',
        endpointId: 'endpoint-1',
      }),
    ).rejects.toThrow('circuit probe failed');
  });
});

describe('Console action auditing', () => {
  const clock: Clock = { nowMs: () => 1_700_000_000_000 };
  const identifiers: IdentifierFactory = { create: () => 'audit-1' };

  const repository = (saved: unknown[], fail = false): PostgresManagementRepository =>
    ({
      saveReplayAudit: async (audit: unknown) => {
        if (fail) {
          throw new Error('management database is unavailable');
        }
        saved.push(audit);
        return audit;
      },
      // biome-ignore lint/suspicious/noExplicitAny: only the audit write is modelled
    }) as any;

  const authorization = {
    sessionId: 'session-1',
    accountId: 'account-1',
    expiresAt: new Date(1_700_000_060_000),
    scope: {
      tenants: ['tenant-1'] as const,
      landscapes: ['base'] as const,
      capabilities: ['events:replay'] as const,
    },
  };

  test('persists a durable audit before the action may be dispatched', async () => {
    const saved: unknown[] = [];
    const auditor = new ManagementReplayAuditor(repository(saved), clock, identifiers);

    const result = await auditor.accept({
      authorization,
      tenantId: 'tenant-1',
      landscape: 'base',
      target: { kind: 'event-replay', eventId: 'event-1' },
      context: {
        requestId: 'request-1',
        sessionId: 'session-1',
        accountId: 'account-1',
        reason: 'customer escalation',
      },
    });

    expect(result.ok).toBe(true);
    expect(saved).toEqual([
      {
        id: 'audit-1',
        accountId: 'account-1',
        tenantId: 'tenant-1',
        landscape: 'base',
        scope: { kind: 'event', eventId: 'event-1' },
        reason: 'customer escalation',
        commandId: 'request-1',
        requestedAt: new Date(1_700_000_000_000),
      },
    ]);
  });

  test('maps circuit re-enable onto an endpoint-scoped audit', async () => {
    const saved: Array<{ scope: unknown }> = [];
    const auditor = new ManagementReplayAuditor(repository(saved as unknown[]), clock, identifiers);

    await auditor.accept({
      authorization,
      tenantId: 'tenant-1',
      landscape: 'base',
      target: { kind: 'circuit-reenable', endpointId: 'endpoint-1' },
      context: {
        requestId: 'request-2',
        sessionId: 'session-1',
        accountId: 'account-1',
        reason: 'operator re-enable',
      },
    });

    expect(saved[0]?.scope).toEqual({ kind: 'endpoint', endpointId: 'endpoint-1' });
  });

  test('rejects a tenant outside the verified scope without writing', async () => {
    const saved: unknown[] = [];
    const auditor = new ManagementReplayAuditor(repository(saved), clock, identifiers);

    const result = await auditor.accept({
      authorization,
      tenantId: 'tenant-2',
      landscape: 'base',
      target: { kind: 'endpoint-replay', endpointId: 'endpoint-1' },
      context: {
        requestId: 'request-3',
        sessionId: 'session-1',
        accountId: 'account-1',
        reason: 'not mine',
      },
    });

    expect(result.ok).toBe(false);
    expect(saved).toEqual([]);
  });

  test('suppresses the action when the audit cannot be durably recorded', async () => {
    const auditor = new ManagementReplayAuditor(repository([], true), clock, identifiers);

    const result = await auditor.accept({
      authorization,
      tenantId: 'tenant-1',
      landscape: 'base',
      target: { kind: 'endpoint-replay', endpointId: 'endpoint-1' },
      context: {
        requestId: 'request-4',
        sessionId: 'session-1',
        accountId: 'account-1',
        reason: 'audit down',
      },
    });

    expect(result.ok).toBe(false);
    expect(result.ok === false && result.error.kind).toBe('unavailable');
  });
});

describe('Provider readiness preflight (H2)', () => {
  const readableEndpoints = { read: async () => Ok(new Uint8Array([1, 2, 3])) };

  test('consults every reference in the ordered credential set, not just the newest', async () => {
    const requested: string[] = [];
    const readers = {
      providerConfigurations: {
        read: async (reference: string) => {
          requested.push(reference);
          // Undefined forces validateProviderConfiguration to reject, but only
          // after every ordered reference has already been read.
          return undefined;
        },
      },
      deliverySecrets: readableEndpoints,
    };

    await expect(
      preflightProviderReadiness(
        [{ provider: 'stripe', verificationSecretRefs: ['live-ref', 'overlap-ref'], endpoints: [] }],
        readers,
      ),
    ).rejects.toThrow();

    // Both the live and overlap references are validated — the reconcile
    // projection no longer collapses the ordered set down to the newest ref.
    expect(requested).toEqual(['live-ref', 'overlap-ref']);
  });

  test('falls back to the singular reference and rejects an unsupported provider before activation', async () => {
    const requested: string[] = [];
    const readers = {
      providerConfigurations: {
        read: async (reference: string) => {
          requested.push(reference);
          return {};
        },
      },
      deliverySecrets: readableEndpoints,
    };

    await expect(
      preflightProviderReadiness(
        [{ provider: 'not-a-provider', verificationSecretRef: 'only-ref', endpoints: [] }],
        readers,
      ),
    ).rejects.toThrow('not-a-provider');
    expect(requested).toEqual(['only-ref']);
  });

  test('the compiler never CASes a generation when the pre-activation preflight rejects', async () => {
    const { MercuryConfigurationCompiler } = await import('../../../src/management/index.ts');
    let staged = false;
    let flipped = false;
    const writer = {
      readActiveConfiguration: async () => undefined,
      writeCompleteGeneration: async () => {
        staged = true;
      },
      flipGeneration: async () => {
        flipped = true;
        return { activated: true, acknowledged: true };
      },
      retainPreviousGeneration: async () => undefined,
    };
    // A repository that lets compilation reach the pre-activation hook.
    const repository = new Proxy(
      {},
      {
        get: (_target, property) => {
          const name = String(property);
          if (name === 'listTenantConfigurations') return async () => [];
          if (name === 'nextConfigGeneration') return async () => 1;
          return async () => undefined;
        },
      },
    );
    const compiler = new MercuryConfigurationCompiler(repository as unknown as never, writer as unknown as never, {
      // A rejection here is exactly what the wired provider-readiness preflight
      // produces for invalid provider/signing material.
      preActivate: async () => {
        throw new Error('provider readiness preflight rejected stripe: configuration-missing');
      },
    });

    await expect(compiler.compileAndPublish(localLandscapeTopology(testConfig()))).rejects.toThrow();

    // The generation is staged, but the CAS/flip is never reached, so the
    // previously active generation is preserved.
    expect(staged).toBe(true);
    expect(flipped).toBe(false);
  });
});

// A real self-signed leaf certificate for shop.example.com (SAN dns), valid
// 2026-07-29T04:12:17Z .. 2036-07-26T04:12:17Z.
const SHOP_CERT_PEM = `-----BEGIN CERTIFICATE-----
MIIDNDCCAhygAwIBAgIUUnSfvFVFCDTPGdm0GxmK9ntKriowDQYJKoZIhvcNAQEL
BQAwGzEZMBcGA1UEAwwQc2hvcC5leGFtcGxlLmNvbTAeFw0yNjA3MjkwNDEyMTda
Fw0zNjA3MjYwNDEyMTdaMBsxGTAXBgNVBAMMEHNob3AuZXhhbXBsZS5jb20wggEi
MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCNnEua3fJDLOQ9XL0crqyU+385
jDxrbutKLMt5lkptMkLkMSneSs4Up/mTNDjN3l1SkfBxBDr6V7pmoc6qn6k/fuVH
JjxMeuChDecr3MFh0XxLO16xL5TPmtBTbkSB61m0tq6qDxTOhhctVHYtw+T8/2T3
TNGkMGHYzau6ePFJD2Z6p4K2w7Sm0sdYKM4QtNeWeWNSrtgJcDP7/YsB3/MwK4q5
5PzkuQ6lf2Qiu+FBYV3S6DmLhigXOWwVCvcgoG90NwhQnqbO0GAEJLS4/hIqjwf4
4NISD3qpcIu7ytMCxWwrMCAjXxyVHmm9SNolMyW8olLcSQjwqJ8BZEmvqK8pAgMB
AAGjcDBuMB0GA1UdDgQWBBT7y4E4CdQLreumjfsGCSUYgiQgUjAfBgNVHSMEGDAW
gBT7y4E4CdQLreumjfsGCSUYgiQgUjAPBgNVHRMBAf8EBTADAQH/MBsGA1UdEQQU
MBKCEHNob3AuZXhhbXBsZS5jb20wDQYJKoZIhvcNAQELBQADggEBAAiQHG57KBfS
dOyXR3qPu3hzsL8WHcZ3+ZGI0S5m2pXBFCyYqzVWD4Nne/7Sci2SnnppdwIiSHrg
bnoJV8BqJnfoWYLYJ/hqKCpWVHhaKBVkJZlfLuYrtrg1uBmW9wi6nqAWNUDN7zK6
9kLn6QHSMYBpdaGn9NU2QIPdN+TgokB87jdQM45QjWIrQ2xbrObD2BIfvaxtLyEP
s5kTS1chJoDvJKKzW5fnth4eKXL3MHRtHhuPUOK493Qt76ia8P1KHEm3608fwZF/
h/vw3Jc2Ma6YSRRfe83z49iBiZXYAGbSO6Yo1DJweG9m5l63qoEyvC1I1brxcbfO
SoG1uHdVE3Q=
-----END CERTIFICATE-----
`;

describe('Custom-domain certificate readiness probe (P0)', () => {
  const certBytes = (): Uint8Array => new TextEncoder().encode(SHOP_CERT_PEM);
  const readerOf = (material: () => ReturnType<SecretReader['read']>) => ({ read: async () => material() });
  const insideValidity = () => new Date('2027-01-01T00:00:00Z');
  const afterValidity = () => new Date('2050-01-01T00:00:00Z');
  const input = { hostname: 'shop.example.com', certificateSecretPointer: '/mercury-domain-abc-tls' };

  test('is fail-closed when the certificate material is missing', async () => {
    const probe = createCertificateReadinessProbe(
      readerOf(async () => Err({ code: 'not-found' as const, message: 'missing' })),
      insideValidity,
    );
    expect(await probe.isReady(input)).toBe(false);
  });

  test('is fail-closed for empty or malformed material', async () => {
    const empty = createCertificateReadinessProbe(
      readerOf(async () => Ok(new Uint8Array(0))),
      insideValidity,
    );
    expect(await empty.isReady(input)).toBe(false);
    const malformed = createCertificateReadinessProbe(
      readerOf(async () =>
        Ok(new TextEncoder().encode('-----BEGIN CERTIFICATE-----\nnope\n-----END CERTIFICATE-----\n')),
      ),
      insideValidity,
    );
    expect(await malformed.isReady(input)).toBe(false);
  });

  test('is fail-closed for an expired certificate', async () => {
    const probe = createCertificateReadinessProbe(
      readerOf(async () => Ok(certBytes())),
      afterValidity,
    );
    expect(await probe.isReady(input)).toBe(false);
  });

  test('is fail-closed when the certificate does not match the hostname', async () => {
    const probe = createCertificateReadinessProbe(
      readerOf(async () => Ok(certBytes())),
      insideValidity,
    );
    expect(await probe.isReady({ ...input, hostname: 'other.example.com' })).toBe(false);
  });

  test('is ready only for valid, unexpired, host-matching certificate material', async () => {
    const probe = createCertificateReadinessProbe(
      readerOf(async () => Ok(certBytes())),
      insideValidity,
    );
    expect(await probe.isReady(input)).toBe(true);
  });
});

describe('Custom-domain ownership verifier (P0)', () => {
  test('is fail-closed: a DNS-proven domain stays unpublished until real certificate readiness', async () => {
    const { DnsDomainOwnershipVerifier, sha256 } = await import('../../../src/management/index.ts');
    const hostname = 'shop.example.com';
    const intakeTarget = 'hooks.mercury.p.mew.cluster.atomi.cloud';
    const challengeTarget = 'mercury-domain-abc.domain-validation.cluster.atomi.cloud';
    const resolver = {
      resolveCname: async (name: string) =>
        name === hostname
          ? [intakeTarget]
          : name === `_acme-challenge.${hostname}`
            ? [challengeTarget]
            : ([] as readonly string[]),
    };
    const input = {
      hostname,
      intakeTarget,
      challengeTarget,
      certificateSecretPointer: '/mercury-domain-abc-tls',
      expectedTokenHash: await sha256(challengeTarget),
    };

    // The exact composition configuration: ownership is proven by DNS, but with
    // no central certificate-readiness authority the domain must remain
    // unpublishable (certificateReady false → the compiler activates only ready
    // domains, so it is never published `active`).
    const failClosed = new DnsDomainOwnershipVerifier({
      resolver,
      certificateReadiness: { isReady: async () => false },
    });
    expect(await failClosed.verify(input)).toEqual({ owned: true, certificateReady: false });

    // Readiness genuinely gates publication — it is consulted, not spuriously
    // false — so a real authority can later flip a proven domain to active.
    const ready = new DnsDomainOwnershipVerifier({
      resolver,
      certificateReadiness: { isReady: async () => true },
    });
    expect(await ready.verify(input)).toEqual({ owned: true, certificateReady: true });
  });
});
