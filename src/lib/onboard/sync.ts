import type { Problem } from '@atomicloud/diene.problems';
import { Err, Ok, Res, type Result, type ResultSerial } from '@atomicloud/diene.result';
import { z } from 'zod';
import { claim, hasRegistrationClaim } from '../jwt';
import {
  type AuthProblems,
  createAuthRefreshFailed,
  createOnboardingClaimMissing,
  createUnauthorized,
} from '../problems';
import {
  type BackendRegistration,
  backendIdSchema,
  type CanonicalResourceKey,
  type ResourceKey,
  type ResourceTree,
  resourceKeySchema,
} from '../resource-tree';
import type { IAuthStateRetriever, TokenSet } from '../retriever';

export type BackendPhase =
  | { readonly kind: 'bootstrapping' }
  | { readonly kind: 'needsOnboarding' }
  | { readonly kind: 'ready' }
  | { readonly kind: 'error'; readonly problem: Problem };

export interface OnboardingApiResponse {
  readonly status: number;
}

export interface CreateUserRequest {
  readonly idToken: string;
  readonly accessToken: string;
  readonly authorization: `Bearer ${string}`;
}

export interface OnboardingBackendApi {
  getMe(accessToken: string): Result<OnboardingApiResponse, Problem>;
  createUser(request: CreateUserRequest): Result<OnboardingApiResponse, Problem>;
}

export interface ApplicationClaimRequirement {
  readonly name: string;
  /** When omitted, the claim must be present in every required resource token. */
  readonly resource?: ResourceKey;
}

export interface OnboardBackendBinding {
  readonly backendId: string;
  readonly api: OnboardingBackendApi;
  readonly applicationClaim?: string | ApplicationClaimRequirement;
}

/** Mutable phase/flight state lives behind this injected port. */
export interface OnboardSyncState {
  getPhase(backendId: string): BackendPhase | undefined;
  setPhase(backendId: string, phase: BackendPhase): void;
  getFlight(backendId: string): Promise<ResultSerial<BackendPhase, Problem>> | undefined;
  setFlight(backendId: string, flight: Promise<ResultSerial<BackendPhase, Problem>>): void;
  deleteFlight(backendId: string, flight: Promise<ResultSerial<BackendPhase, Problem>>): void;
}

export interface OnboardSyncOptions {
  readonly retriever: IAuthStateRetriever;
  readonly resourceTree: Pick<ResourceTree, 'getBackend'>;
  readonly state: OnboardSyncState;
  /** Immutable, complete API bindings; no later registration step exists. */
  readonly bindings: readonly OnboardBackendBinding[];
  readonly problems: Pick<AuthProblems, 'AuthRefreshFailed' | 'OnboardingClaimMissing' | 'Unauthorized'>;
  readonly mapError?: (error: unknown) => Problem;
}

/** Ready onboarding behavior exposed only through the validating factory. */
export interface OnboardSync {
  phase(backendId: unknown): Result<BackendPhase, Problem>;
  phases(): Readonly<Record<string, BackendPhase>>;
  syncBackend(backendId: unknown): Result<BackendPhase, Problem>;
  reportTrafficFailure(backendId: unknown, status: unknown, problem?: Problem): Result<BackendPhase, Problem>;
}

interface OnboardContext extends OnboardSyncOptions {
  readonly mapError: (error: unknown) => Problem;
}

const bootstrapping = Object.freeze({ kind: 'bootstrapping' } as const);
const ready = Object.freeze({ kind: 'ready' } as const);
const needsOnboarding = Object.freeze({ kind: 'needsOnboarding' } as const);

const claimNameSchema = z.string().trim().min(1).max(256);
const applicationClaimSchema = z.union([
  claimNameSchema,
  z
    .object({
      name: claimNameSchema,
      resource: resourceKeySchema.optional(),
    })
    .strict(),
]);

const backendApiSchema = z.custom<OnboardingBackendApi>(
  value =>
    typeof value === 'object' &&
    value !== null &&
    typeof (value as OnboardingBackendApi).getMe === 'function' &&
    typeof (value as OnboardingBackendApi).createUser === 'function',
  'api must implement OnboardingBackendApi',
);

const bindingSchema = z
  .object({
    backendId: backendIdSchema,
    api: backendApiSchema,
    applicationClaim: applicationClaimSchema.optional(),
  })
  .strict();

const onboardOptionsSchema = z
  .object({
    retriever: z.custom<IAuthStateRetriever>(
      value =>
        typeof value === 'object' &&
        value !== null &&
        typeof (value as IAuthStateRetriever).getTokenSet === 'function' &&
        typeof (value as IAuthStateRetriever).forceTokenSet === 'function',
      'retriever must implement IAuthStateRetriever',
    ),
    resourceTree: z.custom<Pick<ResourceTree, 'getBackend'>>(
      value =>
        typeof value === 'object' &&
        value !== null &&
        typeof (value as Pick<ResourceTree, 'getBackend'>).getBackend === 'function',
      'resourceTree must expose getBackend',
    ),
    state: z.custom<OnboardSyncState>(
      value =>
        typeof value === 'object' &&
        value !== null &&
        typeof (value as OnboardSyncState).getPhase === 'function' &&
        typeof (value as OnboardSyncState).setPhase === 'function' &&
        typeof (value as OnboardSyncState).getFlight === 'function' &&
        typeof (value as OnboardSyncState).setFlight === 'function' &&
        typeof (value as OnboardSyncState).deleteFlight === 'function',
      'state must implement OnboardSyncState',
    ),
    bindings: z
      .array(bindingSchema)
      .superRefine((bindings, context) => {
        const ids = bindings.map(binding => binding.backendId);
        if (new Set(ids).size !== ids.length) {
          context.addIssue({ code: 'custom', message: 'onboarding backend ids must be unique' });
        }
      })
      .readonly(),
    problems: z.custom<Pick<AuthProblems, 'AuthRefreshFailed' | 'OnboardingClaimMissing' | 'Unauthorized'>>(
      value =>
        typeof value === 'object' &&
        value !== null &&
        'AuthRefreshFailed' in value &&
        'OnboardingClaimMissing' in value &&
        'Unauthorized' in value,
      'problems must include onboarding problem definitions',
    ),
    mapError: z.custom<(error: unknown) => Problem>(value => typeof value === 'function').optional(),
  })
  .strict();

const tokenSetSchema = z
  .object({
    idToken: z.string().min(1),
    accessTokens: z.record(z.string(), z.string().min(1)),
  })
  .strict();

const apiResponseSchema = z.object({ status: z.number().int().min(100).max(599) }).strict();

const trafficFailureSchema = z
  .object({ backendId: backendIdSchema, status: z.number().int().min(100).max(599) })
  .strict();

function fallbackProblem(error: unknown): Problem {
  return {
    type: 'about:blank',
    title: 'Backend onboarding failed',
    status: 500,
    detail: error instanceof Error ? error.message : 'The backend onboarding operation failed.',
    data: {},
  };
}

function configuredMapError(input: unknown): (error: unknown) => Problem {
  if (typeof input === 'object' && input !== null) {
    if ('mapError' in input && typeof input.mapError === 'function') {
      return input.mapError as (error: unknown) => Problem;
    }
    if ('problems' in input && typeof input.problems === 'object' && input.problems !== null) {
      const problems = input.problems as Partial<Pick<AuthProblems, 'AuthRefreshFailed'>>;
      if (problems.AuthRefreshFailed !== undefined) {
        return error =>
          createAuthRefreshFailed(
            problems as Pick<AuthProblems, 'AuthRefreshFailed'>,
            error instanceof Error ? error.message : 'The backend onboarding request failed.',
          );
      }
    }
  }
  return fallbackProblem;
}

function canonicalResourceKeyOf(resource: ResourceKey): CanonicalResourceKey {
  return `${resource.platform}/${resource.landscape}/${resource.service}/${resource.resourceName}`;
}

function sameResource(left: ResourceKey, right: ResourceKey): boolean {
  return canonicalResourceKeyOf(left) === canonicalResourceKeyOf(right);
}

function cloneResource(resource: ResourceKey): ResourceKey {
  return Object.freeze({ ...resource });
}

function cloneBinding(binding: OnboardBackendBinding): OnboardBackendBinding {
  const requirement = binding.applicationClaim;
  return Object.freeze({
    backendId: binding.backendId,
    api: binding.api,
    applicationClaim:
      typeof requirement === 'object'
        ? Object.freeze({
            name: requirement.name,
            ...(requirement.resource === undefined ? {} : { resource: cloneResource(requirement.resource) }),
          })
        : requirement,
  });
}

function findBinding(bindings: readonly OnboardBackendBinding[], backendId: string): OnboardBackendBinding | undefined {
  return bindings.find(binding => binding.backendId === backendId);
}

function isAcceptedCreate(status: number): boolean {
  return (status >= 200 && status <= 299) || status === 409;
}

function failBackend(context: OnboardContext, backendId: string, problem: Problem): Result<BackendPhase, Problem> {
  context.state.setPhase(backendId, Object.freeze({ kind: 'error', problem }));
  return Err(problem);
}

function validateTokenSet(
  context: OnboardContext,
  backend: BackendRegistration,
  input: unknown,
): Result<TokenSet, Problem> {
  const parsed = tokenSetSchema.safeParse(input);
  if (!parsed.success) return Err(context.mapError(new Error(z.prettifyError(parsed.error))));
  for (const resource of backend.resources) {
    const key = canonicalResourceKeyOf(resource);
    if (parsed.data.accessTokens[key] === undefined) {
      return Err(context.mapError(new Error(`Token set omitted ${key}`)));
    }
  }
  return Ok(parsed.data as TokenSet);
}

function hasEveryRegistrationClaim(
  context: OnboardContext,
  backend: BackendRegistration,
  tokens: TokenSet,
): Result<boolean, Problem> {
  return Res.async(async () => {
    for (const resource of backend.resources) {
      const result = await hasRegistrationClaim(
        tokens.accessTokens[canonicalResourceKeyOf(resource)] as string,
        resource.platform,
        resource.service,
        context.problems.Unauthorized,
      ).serial();
      if (result[0] === 'err') return Err(result[1]);
      if (!result[1]) return Ok(false);
    }
    return Ok(true);
  });
}

function hasApplicationClaim(context: OnboardContext, token: string, name: string): Result<boolean, Problem> {
  return claim<unknown>(token, name, context.problems.Unauthorized).map(value =>
    typeof value === 'string' ? value.trim() !== '' : value !== undefined && value !== null,
  );
}

function hasEveryApplicationClaim(
  context: OnboardContext,
  backend: BackendRegistration,
  binding: OnboardBackendBinding,
  tokens: TokenSet,
): Result<boolean, Problem> {
  return Res.async(async () => {
    const requirement = binding.applicationClaim;
    if (requirement === undefined) return Ok(true);
    const name = typeof requirement === 'string' ? requirement : requirement.name;
    const resources =
      typeof requirement === 'object' && requirement.resource !== undefined
        ? [requirement.resource]
        : backend.resources;
    for (const resource of resources) {
      const result = await hasApplicationClaim(
        context,
        tokens.accessTokens[canonicalResourceKeyOf(resource)] as string,
        name,
      ).serial();
      if (result[0] === 'err') return Err(result[1]);
      if (!result[1]) return Ok(false);
    }
    return Ok(true);
  });
}

function finishRegistered(
  context: OnboardContext,
  backendId: string,
  backend: BackendRegistration,
  binding: OnboardBackendBinding,
  tokens: TokenSet,
): Result<BackendPhase, Problem> {
  return hasEveryApplicationClaim(context, backend, binding, tokens).map(complete => {
    const phase = complete ? ready : needsOnboarding;
    context.state.setPhase(backendId, phase);
    return phase;
  });
}

function parseApiResponse(context: OnboardContext, input: unknown): Result<OnboardingApiResponse, Problem> {
  const parsed = apiResponseSchema.safeParse(input);
  return parsed.success ? Ok(parsed.data) : Err(context.mapError(new Error(z.prettifyError(parsed.error))));
}

function runBackendSync(context: OnboardContext, backendId: string): Result<BackendPhase, Problem> {
  return Res.async(async () => {
    try {
      const binding = findBinding(context.bindings, backendId);
      if (binding === undefined) {
        return failBackend(context, backendId, context.mapError(new Error(`Unknown onboarding backend ${backendId}`)));
      }
      const backendResult = await context.resourceTree.getBackend(backendId).serial();
      if (backendResult[0] === 'err') return failBackend(context, backendId, backendResult[1]);
      const backend = backendResult[1];

      context.state.setPhase(backendId, bootstrapping);
      const initial = await context.retriever.getTokenSet().serial();
      if (initial[0] === 'err') return failBackend(context, backendId, initial[1]);
      if (!initial[1].value.isAuthed) {
        return failBackend(context, backendId, createUnauthorized(context.problems));
      }

      const validated = await validateTokenSet(context, backend, initial[1].value.data).serial();
      if (validated[0] === 'err') return failBackend(context, backendId, validated[1]);
      const tokens = validated[1];
      const initiallyRegistered = await hasEveryRegistrationClaim(context, backend, tokens).serial();
      if (initiallyRegistered[0] === 'err') {
        return failBackend(context, backendId, initiallyRegistered[1]);
      }
      if (initiallyRegistered[1]) {
        const phase = await finishRegistered(context, backendId, backend, binding, tokens).serial();
        return phase[0] === 'ok' ? Ok(phase[1]) : failBackend(context, backendId, phase[1]);
      }

      const onboardingKey = canonicalResourceKeyOf(backend.onboardingResource);
      const accessToken = tokens.accessTokens[onboardingKey] as string;
      const getMeResult = await binding.api.getMe(accessToken).serial();
      if (getMeResult[0] === 'err') return failBackend(context, backendId, getMeResult[1]);
      const parsedGetMe = await parseApiResponse(context, getMeResult[1]).serial();
      if (parsedGetMe[0] === 'err') return failBackend(context, backendId, parsedGetMe[1]);

      if (parsedGetMe[1].status === 404) {
        const createResult = await binding.api
          .createUser({ idToken: tokens.idToken, accessToken, authorization: `Bearer ${accessToken}` })
          .serial();
        if (createResult[0] === 'err') return failBackend(context, backendId, createResult[1]);
        const parsedCreate = await parseApiResponse(context, createResult[1]).serial();
        if (parsedCreate[0] === 'err') return failBackend(context, backendId, parsedCreate[1]);
        if (!isAcceptedCreate(parsedCreate[1].status)) {
          return failBackend(
            context,
            backendId,
            context.mapError(new Error(`Backend ${backendId} create returned ${parsedCreate[1].status}`)),
          );
        }
      } else if (parsedGetMe[1].status !== 200) {
        return failBackend(
          context,
          backendId,
          context.mapError(new Error(`Backend ${backendId} lookup returned ${parsedGetMe[1].status}`)),
        );
      }

      const refreshed = await context.retriever.forceTokenSet().serial();
      if (refreshed[0] === 'err') return failBackend(context, backendId, refreshed[1]);
      if (!refreshed[1].value.isAuthed) {
        return failBackend(
          context,
          backendId,
          createUnauthorized(context.problems, 'Authentication ended during onboarding.'),
        );
      }

      const validatedRefresh = await validateTokenSet(context, backend, refreshed[1].value.data).serial();
      if (validatedRefresh[0] === 'err') {
        return failBackend(context, backendId, validatedRefresh[1]);
      }
      const refreshedTokens = validatedRefresh[1];
      const refreshedRegistration = await hasEveryRegistrationClaim(context, backend, refreshedTokens).serial();
      if (refreshedRegistration[0] === 'err') {
        return failBackend(context, backendId, refreshedRegistration[1]);
      }
      if (!refreshedRegistration[1]) {
        return failBackend(context, backendId, createOnboardingClaimMissing(context.problems, backendId));
      }

      const phase = await finishRegistered(context, backendId, backend, binding, refreshedTokens).serial();
      return phase[0] === 'ok' ? Ok(phase[1]) : failBackend(context, backendId, phase[1]);
    } catch (error: unknown) {
      return failBackend(context, backendId, context.mapError(error));
    }
  });
}

/**
 * Build a ready onboarding coordinator. All bindings are validated and frozen
 * before the service is exposed; dynamic phases/flights remain in `state`.
 */
export function createOnboardSync(input: unknown): Result<OnboardSync, Problem> {
  const mapError = configuredMapError(input);
  const parsed = onboardOptionsSchema.safeParse(input);
  if (!parsed.success) return Err(mapError(new Error(z.prettifyError(parsed.error))));

  return Res.async(async () => {
    try {
      const options = parsed.data as OnboardSyncOptions;
      for (const binding of options.bindings) {
        const backendResult = await options.resourceTree.getBackend(binding.backendId).serial();
        if (backendResult[0] === 'err') return Err(backendResult[1]);
        const requirement = binding.applicationClaim;
        if (
          typeof requirement === 'object' &&
          requirement.resource !== undefined &&
          !backendResult[1].resources.some(resource => sameResource(resource, requirement.resource as ResourceKey))
        ) {
          return Err(
            mapError(
              new Error(`Onboarding backend ${binding.backendId} application-claim resource must be registered`),
            ),
          );
        }
      }

      const context: OnboardContext = Object.freeze({
        ...options,
        bindings: Object.freeze(options.bindings.map(cloneBinding)),
        mapError,
      });
      return Ok(new OnboardSyncService(context));
    } catch (error: unknown) {
      return Err(mapError(error));
    }
  });
}

class OnboardSyncService implements OnboardSync {
  readonly #context: OnboardContext;

  constructor(options: OnboardSyncOptions) {
    this.#context = Object.freeze({
      ...options,
      mapError: options.mapError ?? configuredMapError(options),
    });
  }

  phase(backendId: unknown): Result<BackendPhase, Problem> {
    const parsed = backendIdSchema.safeParse(backendId);
    if (!parsed.success) return Err(this.#context.mapError(new Error(z.prettifyError(parsed.error))));
    if (findBinding(this.#context.bindings, parsed.data) === undefined) {
      return Err(this.#context.mapError(new Error(`Unknown onboarding backend ${parsed.data}`)));
    }
    return Ok(this.#context.state.getPhase(parsed.data) ?? bootstrapping);
  }

  phases(): Readonly<Record<string, BackendPhase>> {
    return Object.freeze(
      Object.fromEntries(
        this.#context.bindings.map(binding => [
          binding.backendId,
          this.#context.state.getPhase(binding.backendId) ?? bootstrapping,
        ]),
      ),
    );
  }

  syncBackend(backendId: unknown): Result<BackendPhase, Problem> {
    const parsed = backendIdSchema.safeParse(backendId);
    if (!parsed.success) return Err(this.#context.mapError(new Error(z.prettifyError(parsed.error))));
    if (findBinding(this.#context.bindings, parsed.data) === undefined) {
      return Err(this.#context.mapError(new Error(`Unknown onboarding backend ${parsed.data}`)));
    }

    return Res.async<BackendPhase, Problem>(async () => {
      const existingFlight = this.#context.state.getFlight(parsed.data);
      if (existingFlight !== undefined) return Res.fromSerial<BackendPhase, Problem>(existingFlight);

      const current = this.#context.state.getPhase(parsed.data);
      if (current?.kind === 'ready' || current?.kind === 'needsOnboarding') return Ok(current);
      if (current?.kind === 'error') return Err(current.problem);

      const flight = runBackendSync(this.#context, parsed.data).serial();
      this.#context.state.setFlight(parsed.data, flight);
      try {
        return Res.fromSerial<BackendPhase, Problem>(await flight);
      } finally {
        this.#context.state.deleteFlight(parsed.data, flight);
      }
    });
  }

  reportTrafficFailure(backendId: unknown, status: unknown, problem?: Problem): Result<BackendPhase, Problem> {
    const parsed = trafficFailureSchema.safeParse({ backendId, status });
    if (!parsed.success) return Err(this.#context.mapError(new Error(z.prettifyError(parsed.error))));
    if (findBinding(this.#context.bindings, parsed.data.backendId) === undefined) {
      return Err(this.#context.mapError(new Error(`Unknown onboarding backend ${parsed.data.backendId}`)));
    }
    if (parsed.data.status !== 401 && parsed.data.status !== 404) {
      return Ok(this.#context.state.getPhase(parsed.data.backendId) ?? bootstrapping);
    }

    const failure =
      problem ?? this.#context.mapError(new Error(`Backend ${parsed.data.backendId} returned ${parsed.data.status}`));
    const phase = Object.freeze({ kind: 'error', problem: failure } as const);
    this.#context.state.setPhase(parsed.data.backendId, phase);
    return Ok(phase);
  }
}
