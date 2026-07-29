import { describe, expect, test } from 'bun:test';
import { ConfigValidationError } from '@atomicloud/diene.config';
import { InMemoryConfigSource } from '@atomicloud/diene.config/test-helper';
import { createMercuryConfigLoader, loadMercuryConfig } from '../../../src/composition/config';
import { initializeMercuryTelemetry } from '../../../src/composition/telemetry';

const shippedConfigDirectory = new URL('../../../config/', import.meta.url).pathname;

const validBase = {
  app: {
    landscape: 'serving',
    platform: 'mercury',
    service: 'webhook',
    module: 'hooks',
    version: '1.0.0',
    bind: '0.0.0.0',
    port: 8080,
    publicOrigin: 'https://hooks.webhook.mercury.mew.cluster.atomi.cloud',
    previewDeliveryVisible: false,
    shutdownGraceMs: 15_000,
  },
  storage: {
    redisUrl: 'redis://upstash.invalid:6379',
    postgresUrl: 'postgres://neon.invalid/mercury',
    archiveEndpoint: 'https://fly.storage.tigris.dev',
    archiveBucket: 'mercury-webhook-archive',
    archiveRegion: 'auto',
  },
  security: {
    consoleSessionSecretFile: '/run/secrets/console',
    managementBootstrapTokenFile: '/run/secrets/management-bootstrap-token',
    providerSecretRoot: '/run/secrets/providers',
    endpointSecretRoot: '/run/secrets/endpoints',
    archiveAccessKeyIdFile: '/run/secrets/archive-access-key-id',
    archiveSecretAccessKeyFile: '/run/secrets/archive-secret-access-key',
    consoleAuthorizationPrivateKeyFile: '/run/secrets/console-authorization-private-key',
    consoleAuthorizationPublicKeyFile: '/run/secrets/console-authorization-public-key',
    managementIssuer: 'mercury',
    managementAudience: 'mercury-management',
  },
  topology: {
    services: {
      'zinc/checkout': {
        module: 'checkout',
        localLandscapes: ['serving'],
        localAddressByLandscape: {
          serving: 'http://checkout.zinc.svc.cluster.local',
        },
        canonicalVlandscape: 'mew',
      },
    },
  },
  providerOperations: {
    apple: {
      enabled: false,
      operationKey: 'apple-notification-history',
      preferredHostLandscape: 'serving',
      intakePath: '/operations/apple/backfill',
      leaseDurationMs: 60_000,
      pageSize: 100,
      intervalMs: 3_600_000,
      jwt: {
        issuerId: '00000000-0000-4000-8000-000000000000',
        keyId: 'KEYID12345',
        bundleId: 'cloud.atomi.example',
        signingKeySecretRef: 'apple-app-store-history.p8',
      },
      history: {
        environment: 'Sandbox',
        request: {
          startDateMs: 0,
          endDateMs: 1,
        },
      },
    },
    google: {
      enabled: false,
      subscriptionName: 'projects/example/subscriptions/mercury-rtdn',
      deadLetterTopic: 'projects/example/topics/mercury-rtdn-dlq',
      deadLetterMaxDeliveryAttempts: 5,
      registeredPushUrl: 'https://hooks.example.test/google/rtdn',
      oidcServiceAccountEmail: 'mercury@example.iam.gserviceaccount.com',
      intervalMs: 3_600_000,
      oauth: {
        credentialSecretRef: 'google-pubsub-service-account.json',
        expectedServiceAccountEmail: 'mercury@example.iam.gserviceaccount.com',
        scopes: ['https://www.googleapis.com/auth/pubsub'],
      },
    },
  },
  otel: {
    logs: {
      enabled: true,
      exporter: {
        console: { enabled: false },
        otlp: { enabled: false, endpoint: '', headers: {}, protocol: 'http/protobuf', timeout: 'PT10S' },
      },
    },
    metrics: {
      enabled: true,
      exporter: {
        console: { enabled: false },
        otlp: { enabled: false, endpoint: '', headers: {}, protocol: 'http/protobuf', timeout: 'PT10S' },
      },
      interval: 'PT60S',
    },
    traces: {
      enabled: true,
      exporter: {
        console: { enabled: false },
        otlp: { enabled: false, endpoint: '', headers: {}, protocol: 'http/protobuf', timeout: 'PT10S' },
      },
      sampler: { ratio: 1, type: 'parentbased_traceidratio' },
    },
  },
} as const;

describe('Mercury configuration composition', () => {
  test('applies the runtime environment last with typed coercion', async () => {
    const source = new InMemoryConfigSource({
      base: validBase,
      runtimeEnv: {
        MERCURY_APP__PORT: '9090',
        MERCURY_APP__PREVIEW_DELIVERY_VISIBLE: 'true',
      },
    });

    const config = await createMercuryConfigLoader({ source, landscape: 'serving' }).load();

    expect(config('app').port).toBe(9090);
    expect(config('app').previewDeliveryVisible).toBe(true);
    expect(config('app').platform).toBe('mercury');
    expect(config('topology').services['zinc/checkout']?.module).toBe('checkout');
  });

  test('projects the typed application identity into the telemetry runtime', async () => {
    const source = new InMemoryConfigSource({
      base: {
        ...validBase,
        otel: {
          logs: { ...validBase.otel.logs, enabled: false },
          metrics: { ...validBase.otel.metrics, enabled: false },
          traces: { ...validBase.otel.traces, enabled: false },
        },
      },
    });
    const config = await createMercuryConfigLoader({ source, landscape: 'serving' }).load();
    const telemetry = initializeMercuryTelemetry(config);

    try {
      expect(telemetry.identity).toEqual({
        landscape: 'serving',
        platform: 'mercury',
        service: 'webhook',
        module: 'hooks',
        version: '1.0.0',
      });
      expect(telemetry.active).toEqual({ logs: false, metrics: false, traces: false });
    } finally {
      await telemetry.shutdown();
    }
  });

  test('ships a valid production provider-operation contract with secret references only', async () => {
    const config = await loadMercuryConfig({ directory: shippedConfigDirectory, environment: {} });
    const operations = config('providerOperations');

    // Both operations are enabled in the shipped default so a chart consumer
    // gets the Apple singleton backfill and Google RTDN reconciliation.
    expect(operations.apple.enabled).toBe(true);
    expect(operations.google.enabled).toBe(true);

    // Apple targets the real production Server API host (environment selects it)
    // and a single preferred-host landscape.
    expect(operations.apple.history.environment).toBe('Production');
    expect(operations.apple.preferredHostLandscape.length).toBeGreaterThan(0);

    // Credentials are references only, never inline material and never invalid
    // placeholder hosts. The -providers ExternalSecret projects flat keys as
    // files directly under providerSecretRoot, so refs must be flat, single-
    // segment, root-confined names (no leading slash, no subdirectory, no
    // traversal) that resolve to a real mounted file.
    expect(operations.apple.jwt.signingKeySecretRef).toBe('apple-app-store-history.p8');
    expect(operations.google.oauth.credentialSecretRef).toBe('google-pubsub-service-account.json');
    for (const ref of [operations.apple.jwt.signingKeySecretRef, operations.google.oauth.credentialSecretRef]) {
      expect(ref.startsWith('/')).toBe(false);
      expect(ref.includes('/')).toBe(false);
      expect(ref.includes('..')).toBe(false);
    }

    const externalHosts = [
      operations.google.registeredPushUrl,
      operations.google.oidcServiceAccountEmail,
      operations.google.oauth.expectedServiceAccountEmail,
      operations.google.subscriptionName,
      operations.google.deadLetterTopic,
    ];
    for (const value of externalHosts) {
      expect(value).not.toContain('.invalid');
      expect(value.toLowerCase()).not.toContain('disabled');
    }
    expect(operations.google.deadLetterMaxDeliveryAttempts).toBeGreaterThanOrEqual(5);
    expect(operations.google.oauth.scopes).toContain('https://www.googleapis.com/auth/pubsub');
  });

  test('returns a Diene Result for validation failures', async () => {
    const source = new InMemoryConfigSource({
      base: {
        ...validBase,
        app: { ...validBase.app, port: 70_000 },
      },
    });

    const result = await createMercuryConfigLoader({ source, landscape: 'serving' }).loadResult();

    expect(await result.isErr()).toBe(true);
    expect(await result.unwrapErr()).toBeInstanceOf(ConfigValidationError);
  });

  test('rejects provider-secret references that are not a single flat mount filename', async () => {
    const withAppleRef = (signingKeySecretRef: string) => ({
      ...validBase,
      providerOperations: {
        ...validBase.providerOperations,
        apple: {
          ...validBase.providerOperations.apple,
          jwt: { ...validBase.providerOperations.apple.jwt, signingKeySecretRef },
        },
      },
    });
    const withGoogleRef = (credentialSecretRef: string) => ({
      ...validBase,
      providerOperations: {
        ...validBase.providerOperations,
        google: {
          ...validBase.providerOperations.google,
          oauth: { ...validBase.providerOperations.google.oauth, credentialSecretRef },
        },
      },
    });

    // Absolute paths, subdirectory slashes, bare/traversing dot segments, and
    // empty references all model refs the flat dataFrom.extract mount cannot
    // resolve and must fail closed at config load.
    const rejectedApple = ['/apple/app-store-history.p8', 'apple/app-store-history.p8', '..', '.', '../escape.p8', ''];
    for (const ref of rejectedApple) {
      const result = await createMercuryConfigLoader({
        source: new InMemoryConfigSource({ base: withAppleRef(ref) }),
        landscape: 'serving',
      }).loadResult();
      expect(await result.isErr()).toBe(true);
    }

    const rejectedGoogle = ['/google/pubsub-service-account.json', 'google/pubsub-service-account.json', '..', ''];
    for (const ref of rejectedGoogle) {
      const result = await createMercuryConfigLoader({
        source: new InMemoryConfigSource({ base: withGoogleRef(ref) }),
        landscape: 'serving',
      }).loadResult();
      expect(await result.isErr()).toBe(true);
    }

    // The flat production names remain valid.
    const accepted = await createMercuryConfigLoader({
      source: new InMemoryConfigSource({ base: withAppleRef('apple-app-store-history.p8') }),
      landscape: 'serving',
    }).loadResult();
    expect(await accepted.isErr()).toBe(false);
  });
});
