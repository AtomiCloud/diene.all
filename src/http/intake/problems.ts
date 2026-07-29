import {
  ProblemRegistry,
  createProblem,
  type ErrorPortalConfig,
  type Problem,
  type RegisteredProblem,
} from '@atomicloud/diene.problems';
import { z } from 'zod';
import type { IntakeFailure } from '../../domain/index.ts';

const routeData = z
  .object({
    tenantId: z.string().min(1).optional(),
    routePath: z.string().startsWith('/'),
  })
  .strict();
const verificationData = routeData.extend({ provider: z.string().min(1) }).strict();
const quotaData = routeData.extend({ retryAfterSeconds: z.number().int().positive() }).strict();
const persistenceData = routeData.extend({ landscape: z.string().min(1) }).strict();
const staleAddressData = z
  .object({
    tenantId: z.string().min(1),
    endpointId: z.string().min(1),
    generation: z.number().int().nonnegative(),
  })
  .strict();

/** Runtime response adapter for the controller-owned published problem catalog. */
export class IntakeProblemCatalog {
  readonly registry: ProblemRegistry;
  readonly unknownRoute: RegisteredProblem<typeof routeData>;
  readonly verificationFailed: RegisteredProblem<typeof verificationData>;
  readonly quotaExhausted: RegisteredProblem<typeof quotaData>;
  readonly persistenceUnavailable: RegisteredProblem<typeof persistenceData>;
  readonly compiledAddressStale: RegisteredProblem<typeof staleAddressData>;

  constructor(portal: ErrorPortalConfig) {
    this.registry = new ProblemRegistry(portal);
    this.unknownRoute = this.registry.register({
      id: 'unknown_route',
      title: 'Webhook route not found',
      status: 404,
      version: 'v1',
      dataSchema: routeData,
    });
    this.verificationFailed = this.registry.register({
      id: 'verification_failed',
      title: 'Provider signature verification failed',
      status: 401,
      version: 'v1',
      dataSchema: verificationData,
    });
    this.quotaExhausted = this.registry.register({
      id: 'quota_exhausted',
      title: 'Webhook intake quota exhausted',
      status: 429,
      version: 'v1',
      dataSchema: quotaData,
    });
    this.persistenceUnavailable = this.registry.register({
      id: 'persistence_unavailable',
      title: 'Webhook event could not be durably recorded',
      status: 503,
      version: 'v1',
      dataSchema: persistenceData,
    });
    this.compiledAddressStale = this.registry.register({
      id: 'compiled_address_stale',
      title: 'Compiled webhook delivery address is stale',
      status: 421,
      version: 'v1',
      dataSchema: staleAddressData,
    });
  }

  fromFailure(failure: IntakeFailure, path: string): Problem {
    const route = {
      routePath: path,
      ...(failure.tenantId === undefined ? {} : { tenantId: failure.tenantId }),
    };
    if (failure.code === 'unknown-route') {
      return createProblem(this.unknownRoute, {
        detail: failure.message,
        instance: path,
        data: route,
      });
    }
    if (failure.code === 'verification-failed') {
      return createProblem(this.verificationFailed, {
        detail: failure.message,
        instance: path,
        data: { ...route, provider: failure.provider ?? 'unknown' },
      });
    }
    if (failure.code === 'quota-exhausted') {
      return createProblem(this.quotaExhausted, {
        detail: failure.message,
        instance: path,
        data: {
          ...route,
          retryAfterSeconds: failure.retryAfterSeconds ?? 1,
        },
      });
    }
    return createProblem(this.persistenceUnavailable, {
      detail: failure.message,
      instance: path,
      data: { ...route, landscape: failure.landscape ?? 'unknown' },
    });
  }
}

export const defaultIntakePortal: ErrorPortalConfig = {
  scheme: 'https',
  host: 'problems.atomi.cloud',
  landscape: 'serving',
  platform: 'mercury',
  service: 'webhook',
  module: 'hooks',
};
