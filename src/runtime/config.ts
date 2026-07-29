import { z } from 'zod';
import { type LandscapeRuntimeConfig, MAX_RETRY_WINDOW_MS } from '../domain/index.ts';

export const MAX_ROUTES_PER_TENANT = 64;
export const MAX_ENDPOINTS_PER_ROUTE = 64;
export const MAX_FANOUT_PER_TENANT = 512;
export const MAX_CONFIG_DOCUMENT_BYTES = 4 * 1_024 * 1_024;
export const MAX_ATOMIC_ACCEPT_COMMAND_BYTES = 4 * 1_024 * 1_024;

const addBytes = (current: number, increment: number, maximumBytes: number): number =>
  current > maximumBytes - increment ? maximumBytes + 1 : current + increment;

const jsonStringByteLength = (value: string, maximumBytes: number): number => {
  let bytes = 2;
  for (let index = 0; index < value.length && bytes <= maximumBytes; index += 1) {
    const code = value.charCodeAt(index);
    if (
      code === 0x22 ||
      code === 0x5c ||
      code === 0x08 ||
      code === 0x09 ||
      code === 0x0a ||
      code === 0x0c ||
      code === 0x0d
    ) {
      bytes = addBytes(bytes, 2, maximumBytes);
    } else if (code <= 0x1f || (code >= 0xd800 && code <= 0xdfff)) {
      if (code >= 0xd800 && code <= 0xdbff) {
        const next = value.charCodeAt(index + 1);
        if (next >= 0xdc00 && next <= 0xdfff) {
          bytes = addBytes(bytes, 4, maximumBytes);
          index += 1;
          continue;
        }
      }
      bytes = addBytes(bytes, 6, maximumBytes);
    } else if (code <= 0x7f) {
      bytes = addBytes(bytes, 1, maximumBytes);
    } else if (code <= 0x7ff) {
      bytes = addBytes(bytes, 2, maximumBytes);
    } else {
      bytes = addBytes(bytes, 3, maximumBytes);
    }
  }
  return bytes;
};

/**
 * Measures JSON UTF-8 bytes without first materializing an attacker-sized JSON
 * string. Values larger than the supplied bound return `bound + 1` early.
 */
export const boundedJsonDocumentByteLength = (value: unknown, maximumBytes: number): number => {
  if (!Number.isSafeInteger(maximumBytes) || maximumBytes < 1) {
    throw new RangeError('JSON document byte bound must be a positive integer');
  }
  const ancestors = new Set<object>();

  const measure = (candidate: unknown, remainingDepth: number, inArray: boolean): number => {
    if (remainingDepth < 0) return maximumBytes + 1;
    if (candidate === null) return 4;
    if (typeof candidate === 'string') return jsonStringByteLength(candidate, maximumBytes);
    if (typeof candidate === 'boolean') return candidate ? 4 : 5;
    if (typeof candidate === 'number') {
      return Number.isFinite(candidate) ? String(candidate).length : 4;
    }
    if (typeof candidate === 'bigint') return maximumBytes + 1;
    if (candidate === undefined || typeof candidate === 'function' || typeof candidate === 'symbol') {
      return inArray ? 4 : 0;
    }
    if (typeof candidate !== 'object' || ancestors.has(candidate)) return maximumBytes + 1;

    ancestors.add(candidate);
    let bytes = 2;
    if (Array.isArray(candidate)) {
      for (let index = 0; index < candidate.length && bytes <= maximumBytes; index += 1) {
        if (index > 0) bytes = addBytes(bytes, 1, maximumBytes);
        bytes = addBytes(bytes, measure(candidate[index], remainingDepth - 1, true), maximumBytes);
      }
    } else {
      let emitted = 0;
      for (const [key, entry] of Object.entries(candidate)) {
        if (entry === undefined || typeof entry === 'function' || typeof entry === 'symbol') continue;
        if (emitted > 0) bytes = addBytes(bytes, 1, maximumBytes);
        bytes = addBytes(bytes, jsonStringByteLength(key, maximumBytes), maximumBytes);
        bytes = addBytes(bytes, 1, maximumBytes);
        bytes = addBytes(bytes, measure(entry, remainingDepth - 1, false), maximumBytes);
        emitted += 1;
        if (bytes > maximumBytes) break;
      }
    }
    ancestors.delete(candidate);
    return bytes;
  };

  return measure(value, 32, false);
};

const isRecord = (value: unknown): value is Readonly<Record<string, unknown>> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

export const runtimeConfigBoundsFailure = (config: LandscapeRuntimeConfig): string | null => {
  if (boundedJsonDocumentByteLength(config, MAX_CONFIG_DOCUMENT_BYTES) > MAX_CONFIG_DOCUMENT_BYTES) {
    return `compiled configuration exceeds ${MAX_CONFIG_DOCUMENT_BYTES} bytes`;
  }
  if (!isRecord(config) || !Array.isArray(config.tenants)) {
    return 'compiled configuration tenant collection is malformed';
  }
  for (const tenant of config.tenants as readonly unknown[]) {
    if (
      !isRecord(tenant) ||
      typeof tenant.id !== 'string' ||
      !Array.isArray(tenant.registeredDomains) ||
      tenant.registeredDomains.some(domain => typeof domain !== 'string') ||
      typeof tenant.intakeRps !== 'number' ||
      typeof tenant.intakeBurst !== 'number' ||
      typeof tenant.retryWindowMs !== 'number' ||
      !Array.isArray(tenant.routes)
    ) {
      return 'compiled tenant entry is malformed';
    }
    if (tenant.routes.length > MAX_ROUTES_PER_TENANT) {
      return `tenant ${tenant.id} exceeds the ${MAX_ROUTES_PER_TENANT} route limit`;
    }
    let fanout = 0;
    for (const route of tenant.routes as readonly unknown[]) {
      if (
        !isRecord(route) ||
        typeof route.id !== 'string' ||
        typeof route.path !== 'string' ||
        typeof route.canonicalPath !== 'string' ||
        typeof route.provider !== 'string' ||
        typeof route.registeredUrl !== 'string' ||
        (route.verificationSecretRef !== undefined &&
          (typeof route.verificationSecretRef !== 'string' || route.verificationSecretRef.trim().length === 0)) ||
        (route.verificationSecretRefs !== undefined &&
          (!Array.isArray(route.verificationSecretRefs) ||
            route.verificationSecretRefs.length === 0 ||
            route.verificationSecretRefs.some(
              reference => typeof reference !== 'string' || reference.trim().length === 0,
            ) ||
            new Set(route.verificationSecretRefs).size !== route.verificationSecretRefs.length)) ||
        !Array.isArray(route.endpoints)
      ) {
        return `tenant ${tenant.id} contains a malformed compiled route`;
      }
      if (route.endpoints.length > MAX_ENDPOINTS_PER_ROUTE) {
        return `route ${route.id} exceeds the ${MAX_ENDPOINTS_PER_ROUTE} endpoint limit`;
      }
      for (const endpoint of route.endpoints as readonly unknown[]) {
        if (
          !isRecord(endpoint) ||
          typeof endpoint.id !== 'string' ||
          typeof endpoint.address !== 'string' ||
          !['canonical', 'external', 'local'].includes(String(endpoint.addressKind)) ||
          typeof endpoint.signingSecretRef !== 'string'
        ) {
          return `route ${route.id} contains a malformed compiled endpoint`;
        }
      }
      fanout += route.endpoints.length;
      if (fanout > MAX_FANOUT_PER_TENANT) {
        return `tenant ${tenant.id} exceeds the ${MAX_FANOUT_PER_TENANT} endpoint fan-out limit`;
      }
    }
  }
  return null;
};

const endpointRegistrationSchema = z
  .object({
    id: z.string().min(1),
    targetKind: z.enum(['coordinate', 'external']),
    canonicalUrl: z.string().url(),
    localUrls: z.record(z.string().min(1), z.string().url()),
    signingSecretRef: z.string().min(1),
  })
  .strict();

const routeRegistrationSchema = z
  .object({
    id: z.string().min(1),
    path: z.string().regex(/^\//),
    provider: z.string().min(1),
    registeredUrl: z.string().url(),
    verificationSecretRef: z.string().min(1).optional(),
    endpoints: z.array(endpointRegistrationSchema).max(MAX_ENDPOINTS_PER_ROUTE),
  })
  .strict()
  .refine(route => new Set(route.endpoints.map(endpoint => endpoint.id)).size === route.endpoints.length, {
    message: 'endpoint ids must be unique within a route',
    path: ['endpoints'],
  });

const tenantRegistrationSchema = z
  .object({
    id: z.string().min(1),
    slug: z.string().regex(/^[A-Za-z0-9._~-]+$/),
    registeredDomains: z.array(z.string().min(1)),
    intakeRps: z.number().positive(),
    intakeBurst: z.number().int().positive(),
    retryWindowMs: z.number().int().positive().max(MAX_RETRY_WINDOW_MS),
    routes: z.array(routeRegistrationSchema).max(MAX_ROUTES_PER_TENANT),
  })
  .strict()
  .refine(tenant => new Set(tenant.routes.map(route => route.id)).size === tenant.routes.length, {
    message: 'route ids must be unique within a tenant',
    path: ['routes'],
  })
  .refine(tenant => new Set(tenant.routes.map(route => route.path)).size === tenant.routes.length, {
    message: 'route paths must be unique within a tenant',
    path: ['routes'],
  })
  .refine(
    tenant => tenant.routes.reduce((count, route) => count + route.endpoints.length, 0) <= MAX_FANOUT_PER_TENANT,
    {
      message: `tenant endpoint fan-out cannot exceed ${MAX_FANOUT_PER_TENANT}`,
      path: ['routes'],
    },
  );

export const registrationSnapshotSchema = z
  .object({
    revision: z.string().min(1),
    tenants: z.array(tenantRegistrationSchema),
  })
  .strict()
  .refine(snapshot => new Set(snapshot.tenants.map(tenant => tenant.id)).size === snapshot.tenants.length, {
    message: 'tenant ids must be unique',
    path: ['tenants'],
  })
  .refine(snapshot => new Set(snapshot.tenants.map(tenant => tenant.slug)).size === snapshot.tenants.length, {
    message: 'tenant slugs must be unique',
    path: ['tenants'],
  });
