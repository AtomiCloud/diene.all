import {
  type Config,
  ConfigLoader,
  ConfigRegistry,
  type ConfigSource,
  type ConfigValidationError,
  YamlConfigSource,
} from '@atomicloud/diene.config';
import { otelBlockSchema } from '@atomicloud/diene.otel';
import type { Result } from '@atomicloud/diene.result';
import { z } from 'zod';

const coordinateSegment = z
  .string()
  .min(1)
  .max(63)
  .regex(/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/);

export const appConfigSchema = z
  .object({
    landscape: coordinateSegment,
    platform: z.literal('mercury'),
    service: z.literal('webhook'),
    module: z.literal('hooks'),
    version: z.string().min(1),
    bind: z.string().min(1),
    port: z.number().int().min(1).max(65_535),
    publicOrigin: z.url(),
    previewDeliveryVisible: z.boolean(),
    shutdownGraceMs: z.number().int().min(1_000).max(120_000),
  })
  .strict()
  .readonly();

const nonEmptyConnectionString = z
  .string()
  .min(1)
  .refine(value => !/\s/.test(value), {
    message: 'connection strings cannot contain whitespace',
  });

export const storageConfigSchema = z
  .object({
    redisUrl: nonEmptyConnectionString,
    postgresUrl: nonEmptyConnectionString,
    archiveEndpoint: z.url(),
    archiveBucket: z.string().min(3).max(63),
    archiveRegion: z.string().min(1),
  })
  .strict()
  .readonly();

export const securityConfigSchema = z
  .object({
    consoleSessionSecretFile: z.string().startsWith('/'),
    managementBootstrapTokenFile: z.string().startsWith('/'),
    providerSecretRoot: z.string().startsWith('/'),
    endpointSecretRoot: z.string().startsWith('/'),
    archiveAccessKeyIdFile: z.string().startsWith('/'),
    archiveSecretAccessKeyFile: z.string().startsWith('/'),
    consoleAuthorizationPrivateKeyFile: z.string().startsWith('/'),
    consoleAuthorizationPublicKeyFile: z.string().startsWith('/'),
    managementIssuer: z.string().min(1),
    managementAudience: z.string().min(1),
  })
  .strict()
  .readonly();

const topologyServiceSchema = z
  .object({
    module: coordinateSegment,
    localLandscapes: z.array(coordinateSegment),
    localAddressByLandscape: z.record(coordinateSegment, z.url()).optional(),
    canonicalVlandscape: coordinateSegment,
    canonicalAddress: z.url().optional(),
  })
  .strict()
  .readonly();

export const topologyConfigSchema = z
  .object({
    services: z.record(z.string().regex(/^[a-z0-9-]+\/[a-z0-9-]+$/), topologyServiceSchema),
  })
  .strict()
  .readonly();

/**
 * A provider-operation credential reference. The `-providers` ExternalSecret
 * uses `dataFrom.extract`, whose rendered Secret has flat keys projected as
 * files directly under `providerSecretRoot` — there is no items/path mapping.
 * The reference must therefore be a single flat mount filename: no absolute
 * path, no slash, and no `.`/`..` traversal segment.
 */
const flatProviderSecretRef = z
  .string()
  .regex(/^[A-Za-z0-9._-]{1,253}$/, 'provider secret reference must be a single flat mount filename')
  .refine(value => value !== '.' && value !== '..' && !value.includes('..'), {
    message: 'provider secret reference must not be a relative or traversing path segment',
  });

const appleProviderOperationSchema = z
  .object({
    enabled: z.boolean(),
    operationKey: z.string().min(1),
    preferredHostLandscape: coordinateSegment,
    intakePath: z.string().startsWith('/'),
    leaseDurationMs: z.number().int().min(1_000).max(600_000),
    pageSize: z.number().int().min(20).optional(),
    intervalMs: z.number().int().min(1_000),
    jwt: z
      .object({
        issuerId: z.uuid(),
        keyId: z.string().regex(/^[A-Z0-9]{10}$/),
        bundleId: z
          .string()
          .regex(/^[A-Za-z0-9][A-Za-z0-9.-]{1,254}$/)
          .refine(value => value.includes('.') && !value.includes('..'), {
            message: 'Apple bundleId must be a reverse-DNS identifier',
          }),
        signingKeySecretRef: flatProviderSecretRef,
        tokenLifetimeSeconds: z.number().int().min(60).max(3_600).optional(),
      })
      .strict()
      .readonly(),
    history: z
      .object({
        environment: z.enum(['Production', 'Sandbox']),
        request: z
          .object({
            startDateMs: z.number().int().nonnegative(),
            endDateMs: z.number().int().nonnegative(),
            onlyFailures: z.boolean().optional(),
            transactionId: z.string().min(1).max(256).optional(),
            notificationType: z.string().min(1).max(256).optional(),
            subtype: z.string().min(1).max(256).optional(),
          })
          .strict()
          .refine(request => request.startDateMs < request.endDateMs, {
            message: 'Apple history startDateMs must precede endDateMs',
          })
          .readonly(),
        timeoutMs: z.number().int().min(1).max(30_000).optional(),
        maxResponseBytes: z.number().int().min(1).max(4_194_304).optional(),
      })
      .strict()
      .readonly(),
  })
  .strict()
  .readonly();

const googleProviderOperationSchema = z
  .object({
    enabled: z.boolean(),
    subscriptionName: z.string().min(1),
    deadLetterTopic: z.string().min(1),
    deadLetterMaxDeliveryAttempts: z.number().int().min(5).max(100),
    registeredPushUrl: z.url(),
    oidcServiceAccountEmail: z.email(),
    oidcAudience: z.string().min(1).optional(),
    intervalMs: z.number().int().min(1_000),
    oauth: z
      .object({
        credentialSecretRef: flatProviderSecretRef,
        expectedServiceAccountEmail: z.email(),
        scopes: z
          .array(z.enum(['https://www.googleapis.com/auth/pubsub', 'https://www.googleapis.com/auth/cloud-platform']))
          .min(1)
          .optional(),
        timeoutMs: z.number().int().min(1).max(30_000).optional(),
        maxResponseBytes: z.number().int().min(1).max(4_194_304).optional(),
        cacheSkewMs: z.number().int().min(0).max(600_000).optional(),
        assertionLifetimeSeconds: z.number().int().min(60).max(3_600).optional(),
      })
      .strict()
      .readonly(),
  })
  .strict()
  .readonly();

export const providerOperationsConfigSchema = z
  .object({
    apple: appleProviderOperationSchema,
    google: googleProviderOperationSchema,
  })
  .strict()
  .readonly();

const mercuryConfigRegistry = ConfigRegistry.create()
  .register('app', appConfigSchema)
  .register('storage', storageConfigSchema)
  .register('security', securityConfigSchema)
  .register('topology', topologyConfigSchema)
  .register('providerOperations', providerOperationsConfigSchema)
  .register('otel', otelBlockSchema);

export type MercuryConfig = Config<{
  app: typeof appConfigSchema;
  storage: typeof storageConfigSchema;
  security: typeof securityConfigSchema;
  topology: typeof topologyConfigSchema;
  providerOperations: typeof providerOperationsConfigSchema;
  otel: typeof otelBlockSchema;
}>;

export interface MercuryConfigLoadOptions {
  readonly source?: ConfigSource;
  readonly directory?: string;
  readonly landscape?: string;
  readonly environment?: Record<string, string | undefined>;
  readonly buildTimeEnvironment?: Record<string, string | undefined>;
}

function defaultConfigDirectory(): string {
  return new URL('../../config/', import.meta.url).pathname;
}

export function createMercuryConfigLoader(options: MercuryConfigLoadOptions = {}): ConfigLoader<{
  app: typeof appConfigSchema;
  storage: typeof storageConfigSchema;
  security: typeof securityConfigSchema;
  topology: typeof topologyConfigSchema;
  providerOperations: typeof providerOperationsConfigSchema;
  otel: typeof otelBlockSchema;
}> {
  const source =
    options.source ??
    new YamlConfigSource({
      dir: options.directory ?? defaultConfigDirectory(),
      baseFile: 'mercury.yaml',
      env: options.environment ?? process.env,
      buildTimeEnv: options.buildTimeEnvironment ?? {},
    });

  return new ConfigLoader(source, mercuryConfigRegistry, {
    prefix: 'MERCURY_',
    landscape: options.landscape ?? options.environment?.MERCURY_LANDSCAPE ?? process.env.MERCURY_LANDSCAPE,
  });
}

export async function loadMercuryConfig(options: MercuryConfigLoadOptions = {}): Promise<MercuryConfig> {
  return createMercuryConfigLoader(options).load();
}

export async function loadMercuryConfigResult(
  options: MercuryConfigLoadOptions = {},
): Promise<Result<MercuryConfig, ConfigValidationError>> {
  return createMercuryConfigLoader(options).loadResult();
}
