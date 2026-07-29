import { afterAll, beforeAll, describe, expect, test } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Ok } from '@atomicloud/diene.result';
import type Redis from 'ioredis';
import {
  createMercuryApplication,
  type MercuryApplication,
  type MercuryCompositionSeams,
  runMercuryDbInit,
} from '../../../src/composition/application.ts';
import type { MercuryConfig } from '../../../src/composition/config.ts';
import type { LandscapeRuntimeConfig } from '../../../src/domain/index.ts';
import { encodeRuntimeConfig } from '../../../src/storage/codec.ts';

const activeConfig: LandscapeRuntimeConfig = {
  generation: 3,
  landscape: 'base',
  compiledAtMs: 1_700_000_000_000,
  sourceRevision: 'content-hash-3',
  tenants: [],
};

let secretRoot: string;
let application: MercuryApplication;
let origin: string;
let server: Bun.Server<undefined> | undefined;

const pem = (label: string, der: Uint8Array): string => {
  const body = Buffer.from(der)
    .toString('base64')
    .replace(/(.{64})/g, '$1\n');
  return `-----BEGIN ${label}-----\n${body.endsWith('\n') ? body : `${body}\n`}-----END ${label}-----\n`;
};

const testConfig = (root: string): MercuryConfig => {
  const blocks: Record<string, unknown> = {
    app: {
      landscape: 'base',
      platform: 'mercury',
      service: 'webhook',
      module: 'hooks',
      version: '1.0.0',
      bind: '127.0.0.1',
      port: 0,
      publicOrigin: 'https://hooks.example.test',
      previewDeliveryVisible: false,
      shutdownGraceMs: 2_000,
    },
    storage: {
      redisUrl: 'redis://127.0.0.1:6379',
      postgresUrl: 'postgres://mercury:mercury@127.0.0.1:5432/mercury',
      archiveEndpoint: 'http://127.0.0.1:9000',
      archiveBucket: 'mercury-webhook-archive',
      archiveRegion: 'us-east-1',
    },
    security: {
      consoleSessionSecretFile: join(root, 'console-session'),
      managementBootstrapTokenFile: join(root, 'management-bootstrap-token'),
      providerSecretRoot: join(root, 'providers'),
      endpointSecretRoot: join(root, 'endpoints'),
      archiveAccessKeyIdFile: join(root, 'archive-access-key-id'),
      archiveSecretAccessKeyFile: join(root, 'archive-secret-access-key'),
      consoleAuthorizationPrivateKeyFile: join(root, 'console-authorization-private-key'),
      consoleAuthorizationPublicKeyFile: join(root, 'console-authorization-public-key'),
      managementIssuer: 'mercury',
      managementAudience: 'mercury-management',
    },
    topology: { services: {} },
    providerOperations: {
      apple: {
        enabled: false,
        operationKey: 'apple-backfill',
        preferredHostLandscape: 'base',
        intakePath: '/t/acme/apple',
        leaseDurationMs: 60_000,
        intervalMs: 3_600_000,
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
        intervalMs: 3_600_000,
      },
    },
    otel: {},
  };
  const accessor = (key: string): unknown => blocks[key];
  return Object.assign(accessor, {
    get: accessor,
    all: () => blocks,
  }) as unknown as MercuryConfig;
};

const stubRedis = (): Redis =>
  new Proxy(
    {},
    {
      get: (_target, property) => {
        const name = String(property);
        if (name === 'ping') return async () => 'PONG';
        if (name === 'set') return async () => 'OK';
        if (name === 'quit') return async () => 'OK';
        if (name === 'get') {
          return async (key: string) =>
            key === 'cfg:gen'
              ? String(activeConfig.generation)
              : key === `cfg:${activeConfig.generation}:landscape`
                ? encodeRuntimeConfig(activeConfig)
                : null;
        }
        return async () => null;
      },
    },
  ) as unknown as Redis;

const stubSql = (): never => {
  const tag = (async () => {
    throw new Error('management database is unavailable');
  }) as unknown as { end: (options?: unknown) => Promise<void> };
  tag.end = async () => undefined;
  return tag as never;
};

const seams = (): MercuryCompositionSeams => ({
  createRedis: () => stubRedis(),
  createSql: () => stubSql(),
  createTelemetry: () =>
    ({
      logger: { error: () => undefined, info: () => undefined, warn: () => undefined },
      traceEmitter: { emit: () => Ok(undefined), flush: () => Ok(undefined) },
      flush: async () => undefined,
      shutdown: async () => undefined,
      // biome-ignore lint/suspicious/noExplicitAny: only the consumed OTel surface is modelled
    }) as any,
  createArchiveStore: () => ({ put: async () => Ok(undefined) as never }),
  serve: options => {
    server = Bun.serve({ hostname: options.hostname, port: 0, fetch: options.fetch });
    return server;
  },
  deliveryTimeoutMs: 1_000,
  deliveryIntervalMs: 3_600_000,
  retentionIntervalMs: 3_600_000,
  reconcileIntervalMs: 3_600_000,
});

beforeAll(async () => {
  secretRoot = await mkdtemp(join(tmpdir(), 'mercury-root-'));
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  await Bun.write(join(secretRoot, 'console-session'), 'x'.repeat(48));
  await Bun.write(join(secretRoot, 'management-bootstrap-token'), 'bootstrap-token-value');
  await Bun.write(join(secretRoot, 'archive-access-key-id'), 'archive-key-id');
  await Bun.write(join(secretRoot, 'archive-secret-access-key'), 'archive-secret-value');
  await Bun.write(
    join(secretRoot, 'console-authorization-private-key'),
    new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey)),
  );
  await Bun.write(
    join(secretRoot, 'console-authorization-public-key'),
    pem('PUBLIC KEY', new Uint8Array(await crypto.subtle.exportKey('spki', pair.publicKey))),
  );
  await Bun.write(join(secretRoot, 'providers', '.keep'), '');
  // Mirrors the chart/SIT mount: tenant endpoint pointers resolve only here.
  await Bun.write(join(secretRoot, 'endpoints', 'coordinate'), 'z'.repeat(48));

  application = await createMercuryApplication(testConfig(secretRoot), seams());
  await application.start();
  origin = `http://127.0.0.1:${server?.port ?? 0}`;
});

afterAll(async () => {
  await application?.shutdown();
  await rm(secretRoot, { recursive: true, force: true });
});

describe('composed Mercury product over a real socket', () => {
  test('answers liveness, startup, and readiness from the local runtime', async () => {
    expect((await fetch(`${origin}/health/live`)).status).toBe(200);
    expect((await fetch(`${origin}/health/startup`)).status).toBe(200);

    const ready = await fetch(`${origin}/health/ready`);
    expect(ready.status).toBe(200);
    const report = (await ready.json()) as {
      ready: boolean;
      dependencies: Record<string, string>;
    };
    expect(report.ready).toBe(true);
    expect(report.dependencies.config).toBe('ok');
    expect(report.dependencies.management).toBe('degraded');
  });

  test('exposes the runtime prometheus registry', async () => {
    const metrics = await fetch(`${origin}/metrics`);
    expect(metrics.headers.get('content-type')).toContain('text/plain');
    expect(await metrics.text()).toContain('mercury_intake_total');
  });

  test('serves the management API with its own health and authentication', async () => {
    const health = await fetch(`${origin}/management/v1/health`);
    expect(health.status).toBe(401);

    const unauthenticated = await fetch(`${origin}/management/v1/tenants`);
    expect(unauthenticated.status).toBe(401);
    expect(unauthenticated.headers.get('www-authenticate')).toContain('Bearer');
  });

  test('requires console-native authorization on the local landscape API', async () => {
    const response = await fetch(`${origin}/internal/landscape/v1/health`);
    expect(response.status).toBe(401);
  });

  test('reserves internal surfaces instead of leaking them to tenant intake', async () => {
    for (const path of ['/health/nope', '/management/v1/nope', '/internal/landscape/v1/nope', '/console/nope']) {
      const response = await fetch(`${origin}${path}`, { method: 'POST', body: '{}' });
      // Every reserved surface answers for itself; none of them may fall
      // through to the tenant intake catch-all, whose only content type is
      // application/problem+json.
      expect([401, 403, 404]).toContain(response.status);
      expect(response.headers.get('content-type')).not.toBe('application/problem+json');
    }
  });

  test('answers unregistered tenant intake from the published problem catalog', async () => {
    const response = await fetch(`${origin}/t/acme/stripe`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{}',
    });

    expect(response.status).toBe(404);
    expect(response.headers.get('content-type')).toBe('application/problem+json');
    const problem = (await response.json()) as { type: string };
    expect(problem.type).toContain('problems.atomi.cloud');
  });
});

describe('composed Mercury db-init', () => {
  test('fails closed when the bootstrap token is absent, without echoing a path', async () => {
    const emptyRoot = await mkdtemp(join(tmpdir(), 'mercury-empty-'));
    try {
      const promise = runMercuryDbInit(testConfig(emptyRoot), {
        createSql: () => stubSql(),
      });
      await expect(promise).rejects.toThrow('management bootstrap token is unavailable');
      await promise.catch((error: unknown) => {
        expect(String(error)).not.toContain(emptyRoot);
      });
    } finally {
      await rm(emptyRoot, { recursive: true, force: true });
    }
  });
});

describe('composed Mercury shutdown', () => {
  test('stops accepting traffic once the bounded shutdown completes', async () => {
    const localSecrets = await mkdtemp(join(tmpdir(), 'mercury-shutdown-'));
    const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
    await Bun.write(join(localSecrets, 'console-session'), 'x'.repeat(48));
    await Bun.write(join(localSecrets, 'management-bootstrap-token'), 'bootstrap-token-value');
    await Bun.write(join(localSecrets, 'archive-access-key-id'), 'archive-key-id');
    await Bun.write(join(localSecrets, 'archive-secret-access-key'), 'archive-secret-value');
    await Bun.write(
      join(localSecrets, 'console-authorization-private-key'),
      new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey)),
    );
    await Bun.write(
      join(localSecrets, 'console-authorization-public-key'),
      new Uint8Array(await crypto.subtle.exportKey('spki', pair.publicKey)),
    );
    await Bun.write(join(localSecrets, 'endpoints', 'coordinate'), 'z'.repeat(48));

    let local: Bun.Server<undefined> | undefined;
    const instance = await createMercuryApplication(testConfig(localSecrets), {
      ...seams(),
      serve: options => {
        local = Bun.serve({ hostname: options.hostname, port: 0, fetch: options.fetch });
        return local;
      },
    });
    await instance.start();
    const localOrigin = `http://127.0.0.1:${local?.port ?? 0}`;
    expect((await fetch(`${localOrigin}/health/live`)).status).toBe(200);

    const start = Date.now();
    await instance.shutdown();

    // In-flight reconcile/provider work and the supervisor drain share ONE
    // grace budget (M7); shutdown must never consume it twice in sequence.
    expect(Date.now() - start).toBeLessThan(2_000 + 2_000);
    expect(instance.startupComplete()).toBe(false);
    expect((await instance.readiness()).ready).toBe(false);
    // Tenant intake is hard-gated the moment shutdown begins, so a provider
    // sees a retryable problem instead of a half-drained acceptance.
    const refused = await fetch(`${localOrigin}/t/acme/stripe`, { method: 'POST', body: '{}' });
    expect(refused.status).toBe(503);
    expect(refused.headers.get('retry-after')).toBe('1');

    await rm(localSecrets, { recursive: true, force: true });
  });
});
