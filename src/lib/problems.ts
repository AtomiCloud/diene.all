import {
  buildProblemTypeUri,
  createProblem,
  fromError,
  type Problem,
  type ProblemDefinition,
  ProblemRegistry,
  type RegisteredProblem,
} from '@atomicloud/diene.problems';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { z } from 'zod';

export const API_PROBLEM_VERSION = 'v1';

const backendDataSchema = z.object({ backend: z.string() }).strict();
const reasonDataSchema = z.object({ backend: z.string(), reason: z.string() }).strict();
const upstreamDataSchema = z.object({ backend: z.string(), status: z.number().int().min(100).max(599) }).strict();

export const ApiConfigurationFailure = Object.freeze({
  id: 'api_configuration_failure',
  title: 'API configuration failure',
  status: 500,
  version: API_PROBLEM_VERSION,
  dataSchema: reasonDataSchema,
});

export const ApiBackendNotFound = Object.freeze({
  id: 'api_backend_not_found',
  title: 'API backend not found',
  status: 404,
  version: API_PROBLEM_VERSION,
  dataSchema: backendDataSchema,
});

export const ApiAuthenticationFailure = Object.freeze({
  id: 'api_authentication_failure',
  title: 'API authentication failure',
  status: 401,
  version: API_PROBLEM_VERSION,
  dataSchema: reasonDataSchema,
});

export const ApiTransportFailure = Object.freeze({
  id: 'api_transport_failure',
  title: 'API transport failure',
  status: 503,
  version: API_PROBLEM_VERSION,
  dataSchema: reasonDataSchema,
});

export const ApiUpstreamFailure = Object.freeze({
  id: 'api_upstream_failure',
  title: 'API upstream failure',
  status: 502,
  version: API_PROBLEM_VERSION,
  dataSchema: upstreamDataSchema,
});

export interface ApiProblems {
  readonly ConfigurationFailure: RegisteredProblem<typeof reasonDataSchema>;
  readonly BackendNotFound: RegisteredProblem<typeof backendDataSchema>;
  readonly AuthenticationFailure: RegisteredProblem<typeof reasonDataSchema>;
  readonly TransportFailure: RegisteredProblem<typeof reasonDataSchema>;
  readonly UpstreamFailure: RegisteredProblem<typeof upstreamDataSchema>;
}

function registrationFailure(registry: ProblemRegistry, error: unknown): Problem {
  const fallbackRegistry = new ProblemRegistry(registry.portal);
  const fallback = fallbackRegistry.register(ApiConfigurationFailure);
  return fromError(error, {
    fallback,
    fallbackData: failure => ({
      backend: 'api-engine',
      reason:
        failure instanceof Error
          ? failure.message
          : typeof failure === 'string'
            ? failure
            : 'API problem definitions could not be registered.',
    }),
  });
}

function register<TSchema extends z.ZodType>(
  registry: ProblemRegistry,
  definition: ProblemDefinition<TSchema>,
): RegisteredProblem<TSchema> {
  const expectedType = buildProblemTypeUri(registry.portal, definition.version, definition.id);
  const existing = registry.get(definition.id, definition.version);
  if (existing !== undefined) {
    if (
      existing.type !== expectedType ||
      existing.title !== definition.title ||
      existing.status !== definition.status ||
      JSON.stringify(z.toJSONSchema(existing.dataSchema)) !== JSON.stringify(z.toJSONSchema(definition.dataSchema))
    ) {
      throw new Error(
        `Problem ${definition.id}@${definition.version} is already registered with a different contract.`,
      );
    }
    return existing as RegisteredProblem<TSchema>;
  }
  return registry.register(definition);
}

/** Register (or compatibly reuse) every problem emitted by api-engine. */
export function registerApiProblems(registry: ProblemRegistry): Result<ApiProblems, Problem> {
  try {
    return Ok(
      Object.freeze({
        ConfigurationFailure: register(registry, ApiConfigurationFailure),
        BackendNotFound: register(registry, ApiBackendNotFound),
        AuthenticationFailure: register(registry, ApiAuthenticationFailure),
        TransportFailure: register(registry, ApiTransportFailure),
        UpstreamFailure: register(registry, ApiUpstreamFailure),
      }),
    );
  } catch (error) {
    return Err(registrationFailure(registry, error));
  }
}

export function createConfigurationProblem(
  problems: Pick<ApiProblems, 'ConfigurationFailure'>,
  backend: string,
  reason: string,
): Problem {
  return createProblem(problems.ConfigurationFailure, { detail: reason, data: { backend, reason } });
}

export function createBackendNotFoundProblem(problems: Pick<ApiProblems, 'BackendNotFound'>, backend: string): Problem {
  return createProblem(problems.BackendNotFound, {
    detail: `No API backend is registered for ${backend}.`,
    data: { backend },
  });
}

export function createAuthenticationProblem(
  problems: Pick<ApiProblems, 'AuthenticationFailure'>,
  backend: string,
  reason: string,
): Problem {
  return createProblem(problems.AuthenticationFailure, { detail: reason, data: { backend, reason } });
}

export function createTransportProblem(
  problems: Pick<ApiProblems, 'TransportFailure'>,
  backend: string,
  reason: string,
): Problem {
  return createProblem(problems.TransportFailure, { detail: reason, data: { backend, reason } });
}

export function createUpstreamProblem(
  problems: Pick<ApiProblems, 'UpstreamFailure'>,
  backend: string,
  status: number,
  detail: string,
): Problem {
  return createProblem(problems.UpstreamFailure, {
    detail,
    status,
    data: { backend, status },
  });
}
