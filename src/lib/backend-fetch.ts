import type { AuthState, CanonicalResourceKey, IAuthStateRetriever, TokenSet } from '@atomicloud/diene.auth-engine';
import { isRecord } from '@atomicloud/diene.core-utils';
import type { Problem } from '@atomicloud/diene.problems';

import { type ApiProblems, createAuthenticationProblem, createTransportProblem } from './problems';
import type { FetchLike, LpsmCoordinate, LpsmKey, RescueTrip } from './types';

export interface BackendFetchOptions {
  readonly backend: LpsmCoordinate;
  readonly backendKey: LpsmKey;
  readonly baseUrl: string;
  readonly resourceKey: CanonicalResourceKey;
  readonly auth: IAuthStateRetriever;
  readonly problems: ApiProblems;
  readonly fetch: FetchLike;
  readonly timeoutMs: number;
  readonly rescue?: RescueTrip;
}

class ApiBoundaryError extends Error {
  readonly problem: Problem;

  constructor(problem: Problem) {
    super(problem.detail ?? problem.title);
    this.name = 'ApiBoundaryError';
    this.problem = problem;
  }
}

function hasReceivedStatus(error: unknown): boolean {
  let current = error;
  const visited = new Set<object>();

  while ((typeof current === 'object' && current !== null) || typeof current === 'function') {
    if (current instanceof Response) return true;
    if (visited.has(current)) return false;
    visited.add(current);

    if (isRecord(current)) {
      for (const field of ['status', 'statusCode', 'responseStatusCode'] as const) {
        const status = current[field];
        if (typeof status === 'number' && Number.isInteger(status) && status >= 100 && status <= 599) {
          return true;
        }
      }
      if (current.response instanceof Response) return true;
    }

    current = (current as { readonly cause?: unknown }).cause;
  }

  return false;
}

async function readAuthState(
  operation: () => ReturnType<IAuthStateRetriever['getTokenSet']>,
): Promise<readonly ['ok', AuthState<TokenSet>] | readonly ['err', Problem]> {
  return operation().serial();
}

async function accessToken(options: BackendFetchOptions): Promise<string> {
  const read = async (
    operation: () => ReturnType<IAuthStateRetriever['getTokenSet']>,
  ): Promise<string | Problem | undefined> => {
    const serial = await readAuthState(operation);
    if (serial[0] === 'err') return serial[1];
    const state = serial[1];
    if (state.__kind === 'unauthed') return undefined;
    return state.value.data.accessTokens[options.resourceKey];
  };

  try {
    const current = await read(() => options.auth.getTokenSet());
    if (typeof current === 'string' && current !== '') return current;
    if (typeof current === 'object' && current !== null) throw new ApiBoundaryError(current);

    const forced = await read(() => options.auth.forceTokenSet());
    if (typeof forced === 'string' && forced !== '') return forced;
    if (typeof forced === 'object' && forced !== null) throw new ApiBoundaryError(forced);

    throw new ApiBoundaryError(
      createAuthenticationProblem(
        options.problems,
        options.backendKey,
        `No access token is available for resource ${options.resourceKey}.`,
      ),
    );
  } catch (error) {
    if (error instanceof ApiBoundaryError) throw error;
    throw new ApiBoundaryError(
      createAuthenticationProblem(
        options.problems,
        options.backendKey,
        error instanceof Error ? error.message : 'Authentication state could not be read.',
      ),
    );
  }
}

type Attempt =
  | { readonly kind: 'response'; readonly response: Response }
  | { readonly kind: 'failure'; readonly error: unknown }
  | { readonly kind: 'abort'; readonly reason: string };

type AttemptRequest = Parameters<FetchLike>[0] & { readonly signal: AbortSignal };

function isAborted(signal: AbortSignal | null | undefined): boolean {
  return signal?.aborted === true;
}

async function attempt(fetch: FetchLike, request: AttemptRequest, timeoutMs: number): Promise<Attempt> {
  const controller = new AbortController();
  let timedOut = false;
  const sourceSignal = request.signal;
  if (isAborted(sourceSignal)) {
    return { kind: 'abort', reason: 'Request was aborted before a response was received.' };
  }
  const abort = () => controller.abort();
  sourceSignal?.addEventListener('abort', abort, { once: true });

  const timer = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, timeoutMs);

  try {
    const response = await fetch(request, { signal: controller.signal });
    return { kind: 'response', response };
  } catch (error) {
    if (timedOut) return { kind: 'abort', reason: `Request timed out after ${timeoutMs}ms.` };
    if (isAborted(sourceSignal) || controller.signal.aborted) {
      return { kind: 'abort', reason: 'Request was aborted before a response was received.' };
    }
    return { kind: 'failure', error };
  } finally {
    clearTimeout(timer);
    sourceSignal?.removeEventListener('abort', abort);
  }
}

/**
 * Attach one backend's token and failure policy to fetch. Only an opaque failure with
 * no received HTTP status is retried, and it is retried exactly once.
 */
export function createBackendFetch(options: BackendFetchOptions): FetchLike {
  return async (input, init) => {
    const token = await accessToken(options);
    const headers = new Headers(input instanceof Request ? input.headers : undefined);
    if (init?.headers !== undefined) {
      for (const [name, value] of new Headers(init.headers)) headers.set(name, value);
    }
    // Always replace a caller-provided bearer token so credentials cannot bleed across backends.
    headers.set('authorization', `Bearer ${token}`);

    const authorizedInit: RequestInit = { ...init, headers };
    const authorizedRequest =
      input instanceof Request ? new Request(input, authorizedInit) : new Request(input.toString(), authorizedInit);
    // Clone both attempts before either fetch can consume the body stream.
    const firstRequest = authorizedRequest.clone() as unknown as AttemptRequest;
    const secondRequest = authorizedRequest.clone() as unknown as AttemptRequest;

    const first = await attempt(options.fetch, firstRequest, options.timeoutMs);
    if (first.kind === 'response') return first.response;
    if (first.kind === 'abort') {
      throw new ApiBoundaryError(createTransportProblem(options.problems, options.backendKey, first.reason));
    }
    if (hasReceivedStatus(first.error)) throw first.error;

    const second = await attempt(options.fetch, secondRequest, options.timeoutMs);
    if (second.kind === 'response') return second.response;
    if (second.kind === 'abort') {
      throw new ApiBoundaryError(createTransportProblem(options.problems, options.backendKey, second.reason));
    }
    if (hasReceivedStatus(second.error)) throw second.error;

    if (options.rescue?.enabled === true) {
      try {
        await options.rescue.trip({
          backend: options.backend,
          backendKey: options.backendKey,
          baseUrl: options.baseUrl,
          attempts: 2,
          error: second.error,
        });
      } catch {
        // Rescue routing belongs to the application; preserve the original transport fact.
      }
    }

    const detail = second.error instanceof Error ? second.error.message : 'Opaque network failure.';
    throw new ApiBoundaryError(
      createTransportProblem(options.problems, options.backendKey, `Both opaque transport attempts failed: ${detail}`),
    );
  };
}
