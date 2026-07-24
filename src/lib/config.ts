import { resourceKeySchema, type IAuthStateRetriever } from '@atomicloud/diene.auth-engine';
import { z } from 'zod';

import { validateBaseUrl } from './lpsm';
import type { BackendClientContext, RescueTrip, RetryProfile } from './types';

export const DEFAULT_BACKEND_TIMEOUT_MS = 15_000;
export const OPAQUE_NETWORK_RETRY_ONCE = 'opaque-network-once' satisfies RetryProfile;

const coordinatePartSchema = z
  .string()
  .trim()
  .min(1)
  .refine(value => !value.includes('/'), {
    error: 'LPSM coordinate parts cannot contain a slash.',
  });

export const lpsmCoordinateSchema = z
  .object({
    landscape: coordinatePartSchema,
    platform: coordinatePartSchema,
    service: coordinatePartSchema,
    module: coordinatePartSchema,
  })
  .strict();

export const backendBaseUrlSchema = z
  .custom<string>(value => validateBaseUrl(value).ok, {
    error: 'baseUrl must be one absolute HTTP(S) URL with a hostname and no credentials.',
  })
  .transform(value => {
    const parsed = validateBaseUrl(value);
    return parsed.ok ? parsed.baseUrl : value;
  });

function isAuthBinding(value: unknown): value is IAuthStateRetriever {
  if (typeof value !== 'object' || value === null) return false;
  const candidate = value as Readonly<Record<string, unknown>>;
  return ['getTokenSet', 'getClaims', 'getUserInfo', 'getStates', 'forceTokenSet'].every(
    method => typeof candidate[method] === 'function',
  );
}

const authBindingSchema = z.custom<IAuthStateRetriever>(isAuthBinding, 'auth must implement IAuthStateRetriever.');
const clientFactorySchema = z.custom<(context: BackendClientContext) => object>(
  value => typeof value === 'function',
  'createClient must be a synchronous client factory.',
);
const rescueTripSchema = z
  .object({
    enabled: z.boolean(),
    trip: z.custom<RescueTrip['trip']>(value => typeof value === 'function', 'rescue.trip must be a function.'),
  })
  .strict();

/**
 * Engine-owned backend block. Applications compose this schema into their config root;
 * api-engine keeps retry behavior fixed and receives auth/client/rescue collaborators.
 */
export const apiEngineConfigBlockSchema = z
  .object({
    coordinate: lpsmCoordinateSchema,
    baseUrl: backendBaseUrlSchema,
    resource: resourceKeySchema,
    timeoutMs: z.number().finite().positive().default(DEFAULT_BACKEND_TIMEOUT_MS),
    retry: z.literal(OPAQUE_NETWORK_RETRY_ONCE).default(OPAQUE_NETWORK_RETRY_ONCE),
    auth: authBindingSchema,
    createClient: clientFactorySchema,
    rescue: rescueTripSchema.optional(),
  })
  .strict();

export type ApiEngineConfigBlock = z.input<typeof apiEngineConfigBlockSchema>;
export type ResolvedApiEngineConfigBlock = z.output<typeof apiEngineConfigBlockSchema>;
