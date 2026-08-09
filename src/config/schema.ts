import { apiEngineConfigBlockSchema } from '@atomicloud/diene.e2e/api';
import { authEngineConfigSchema } from '@atomicloud/diene.e2e/auth';
import { ConfigRegistry, type ConfigData } from '@atomicloud/diene.e2e/config';
import { appIdentitySchema, otelBlockSchema } from '@atomicloud/diene.e2e/otel';
import { registerStandardConfigs } from '@atomicloud/diene.e2e/standard-config';
import { z } from 'zod';

const apiBackendSchema = apiEngineConfigBlockSchema
  .pick({
    coordinate: true,
    resource: true,
    retry: true,
    timeoutMs: true,
  })
  .extend({ baseUrl: z.url() });

const apiConfigSchema = z
  .object({
    backends: z.array(apiBackendSchema).min(1),
  })
  .strict();

const encryptionConfigSchema = z.object({ key: z.string() }).strict();

const transportConfigSchema = z
  .object({
    batchSize: z.coerce.number().int().min(1).max(100),
    blockMs: z.coerce.number().int().min(1).max(60_000),
    consumerGroup: z.string().trim().min(1),
    consumerName: z.string().trim().min(1),
    idleMs: z.coerce.number().int().min(0),
    stream: z.string().trim().min(1),
  })
  .strict();

const errorPortalConfigSchema = z
  .object({
    host: z.string().trim().min(1),
    landscape: z.string().trim().min(1),
    module: z.string().trim().min(1),
    platform: z.string().trim().min(1),
    scheme: z.enum(['http', 'https']),
    service: z.string().trim().min(1),
    version: z.string().regex(/^v\d+$/),
  })
  .strict();

const domainConfigSchema = z
  .object({
    blobPrefix: z.string().trim().min(1),
    maxMessageBytes: z.coerce.number().int().min(1),
  })
  .strict();

const dbInitConfigSchema = z
  .object({
    createBucket: z.boolean(),
    migrationsDir: z.string().trim().min(1),
    redisMigrationKey: z.string().trim().min(1),
    seedDir: z.string().trim().min(1),
  })
  .strict();

const healthConfigSchema = z
  .object({
    heartbeatFile: z.string().trim().min(1),
    maxAgeMs: z.coerce.number().int().min(1),
  })
  .strict();

export const applicationRegistry = registerStandardConfigs(ConfigRegistry.create(), {
  which: ['postgres', 'cache', 'kv', 'storage'] as const,
})
  .register('app', appIdentitySchema)
  .register('otel', otelBlockSchema)
  .register('auth', authEngineConfigSchema)
  .register('api', apiConfigSchema)
  .register('encryption', encryptionConfigSchema)
  .register('transport', transportConfigSchema)
  .register('errorPortal', errorPortalConfigSchema)
  .register('domain', domainConfigSchema)
  .register('dbInit', dbInitConfigSchema)
  .register('health', healthConfigSchema);

type RegistryShape = typeof applicationRegistry extends ConfigRegistry<infer Shape> ? Shape : never;

export type ApplicationConfig = ConfigData<RegistryShape>;
