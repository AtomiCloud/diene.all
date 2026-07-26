import {
  buildProblemTypeUri,
  createProblem,
  type Problem,
  type ProblemDefinition,
  type ProblemRegistry,
  type RegisteredProblem,
  Unauthorized,
} from '@atomicloud/diene.problems';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { z } from 'zod';

export const AUTH_PROBLEM_VERSION = 'v1';
export const APP_HANDOFF_EXPIRED_DETAIL = 'This app handoff is expired or invalid.';

const emptyDataSchema = z.object({}).strict();

export const AppHandoffExpired = Object.freeze({
  id: 'app_handoff_expired',
  title: 'App handoff expired',
  status: 410,
  version: AUTH_PROBLEM_VERSION,
  dataSchema: emptyDataSchema,
}) satisfies ProblemDefinition<typeof emptyDataSchema>;

export const OnboardingClaimMissing = Object.freeze({
  id: 'onboarding_claim_missing',
  title: 'Onboarding claim missing',
  status: 409,
  version: AUTH_PROBLEM_VERSION,
  dataSchema: emptyDataSchema,
}) satisfies ProblemDefinition<typeof emptyDataSchema>;

export const AuthRefreshFailed = Object.freeze({
  id: 'auth_refresh_failed',
  title: 'Authentication refresh failed',
  status: 502,
  version: AUTH_PROBLEM_VERSION,
  dataSchema: emptyDataSchema,
}) satisfies ProblemDefinition<typeof emptyDataSchema>;

export const InvalidReturnTo = Object.freeze({
  id: 'invalid_return_to',
  title: 'Invalid returnTo',
  status: 400,
  version: AUTH_PROBLEM_VERSION,
  dataSchema: emptyDataSchema,
}) satisfies ProblemDefinition<typeof emptyDataSchema>;

type EmptyProblem = RegisteredProblem<typeof emptyDataSchema>;
type UnauthorizedProblem = RegisteredProblem<typeof Unauthorized.dataSchema>;

export interface AuthProblems {
  readonly AppHandoffExpired: EmptyProblem;
  readonly OnboardingClaimMissing: EmptyProblem;
  readonly AuthRefreshFailed: EmptyProblem;
  readonly InvalidReturnTo: EmptyProblem;
  readonly Unauthorized: UnauthorizedProblem;
}

function registerOrReuse<TSchema extends z.ZodType>(
  registry: ProblemRegistry,
  definition: ProblemDefinition<TSchema>,
): RegisteredProblem<TSchema> {
  const existing = registry.get(definition.id, definition.version);
  return (existing as RegisteredProblem<TSchema> | undefined) ?? registry.register(definition);
}

function assertCompatibleRegistration<TSchema extends z.ZodType>(
  registry: ProblemRegistry,
  definition: ProblemDefinition<TSchema>,
): void {
  const expectedType = buildProblemTypeUri(registry.portal, definition.version, definition.id);
  const existing = registry.get(definition.id, definition.version);
  if (existing === undefined) return;
  const sameSchema =
    JSON.stringify(z.toJSONSchema(existing.dataSchema)) === JSON.stringify(z.toJSONSchema(definition.dataSchema));
  if (
    existing.type !== expectedType ||
    existing.title !== definition.title ||
    existing.status !== definition.status ||
    !sameSchema
  ) {
    throw new Error(`Problem ${definition.id}@${definition.version} is already registered with a different contract.`);
  }
}

function authProblemRegistrationFailure(): Problem {
  return Object.freeze({
    type: 'about:blank',
    title: AuthRefreshFailed.title,
    status: AuthRefreshFailed.status,
    detail: 'Authentication problem definitions could not be registered.',
    data: {},
  });
}

export function registerAuthProblems(registry: ProblemRegistry): Result<AuthProblems, Problem> {
  try {
    const unauthorized = { ...Unauthorized, version: AUTH_PROBLEM_VERSION };
    // Preflight every existing definition and URI before mutating the registry,
    // so a late conflict cannot leave a partially registered auth catalog.
    assertCompatibleRegistration(registry, AppHandoffExpired);
    assertCompatibleRegistration(registry, OnboardingClaimMissing);
    assertCompatibleRegistration(registry, AuthRefreshFailed);
    assertCompatibleRegistration(registry, InvalidReturnTo);
    assertCompatibleRegistration(registry, unauthorized);
    return Ok(
      Object.freeze({
        AppHandoffExpired: registerOrReuse(registry, AppHandoffExpired),
        OnboardingClaimMissing: registerOrReuse(registry, OnboardingClaimMissing),
        AuthRefreshFailed: registerOrReuse(registry, AuthRefreshFailed),
        InvalidReturnTo: registerOrReuse(registry, InvalidReturnTo),
        Unauthorized: registerOrReuse(registry, unauthorized),
      }),
    );
  } catch {
    return Err(authProblemRegistrationFailure());
  }
}

export function createAppHandoffExpired(problems: Pick<AuthProblems, 'AppHandoffExpired'>): Problem {
  return createProblem(problems.AppHandoffExpired, {
    detail: APP_HANDOFF_EXPIRED_DETAIL,
    data: {},
  });
}

export function createOnboardingClaimMissing(
  problems: Pick<AuthProblems, 'OnboardingClaimMissing'>,
  backendId?: string,
): Problem {
  return createProblem(problems.OnboardingClaimMissing, {
    detail:
      backendId === undefined
        ? 'The registration claim was still missing after token refresh.'
        : `The registration claim for backend ${backendId} was still missing after token refresh.`,
    data: {},
  });
}

export function createAuthRefreshFailed(
  problems: Pick<AuthProblems, 'AuthRefreshFailed'>,
  detail = 'The authentication token could not be refreshed.',
): Problem {
  return createProblem(problems.AuthRefreshFailed, { detail, data: {} });
}

export function createInvalidReturnTo(
  problems: Pick<AuthProblems, 'InvalidReturnTo'>,
  detail = 'The requested continuation URL is invalid.',
): Problem {
  return createProblem(problems.InvalidReturnTo, { detail, data: {} });
}

export function createUnauthorized(
  problems: Pick<AuthProblems, 'Unauthorized'>,
  reason = 'Authentication is required.',
): Problem {
  return createProblem(problems.Unauthorized, {
    detail: reason,
    data: { reason },
  });
}
