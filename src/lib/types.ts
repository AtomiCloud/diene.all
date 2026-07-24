import type { CanonicalResourceKey, IAuthStateRetriever, ResourceKey } from '@atomicloud/diene.auth-engine';
import type { Problem } from '@atomicloud/diene.problems';
import type { Result } from '@atomicloud/diene.result';

import type { ApiProblems } from './problems';

/** The complete service-tree address used to register and resolve one SDK backend. */
export interface LpsmCoordinate {
  readonly landscape: string;
  readonly platform: string;
  readonly service: string;
  readonly module: string;
}

export type LpsmKey = `${string}/${string}/${string}/${string}`;

/** Web-standard fetch surface accepted by Kiota request adapters. */
export type FetchLike = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;

export interface BackendClientContext {
  /** The sole configured address for this backend. Runtime callers cannot replace it. */
  readonly baseUrl: string;
  /** Fetch with this backend's auth, timeout, retry, and rescue-trip policy attached. */
  readonly fetch: FetchLike;
}

export interface RescueTripContext {
  readonly backend: LpsmCoordinate;
  readonly backendKey: LpsmKey;
  readonly baseUrl: string;
  readonly attempts: 2;
  readonly error: unknown;
}

/**
 * Optional hand-off to an application-owned rescue router. Api-engine only reports a
 * trip; it deliberately owns no routing or failover policy.
 */
export interface RescueTrip {
  readonly enabled: boolean;
  trip(context: RescueTripContext): void | Promise<void>;
}

export interface BackendBinding<TClient extends object = object> {
  readonly coordinate: LpsmCoordinate;
  readonly baseUrl: string;
  readonly resource: ResourceKey;
  readonly auth: IAuthStateRetriever;
  readonly createClient: (context: BackendClientContext) => TClient;
  readonly timeoutMs?: number;
  readonly rescue?: RescueTrip;
}

export interface ApiEngineOptions {
  /** Immutable, complete registration list. There is no later mutation step. */
  readonly bindings: readonly BackendBinding[];
  readonly problems: ApiProblems;
  readonly fetch?: FetchLike;
}

type ReconciledReturn<TReturn> =
  Awaited<TReturn> extends Result<infer TValue, unknown>
    ? TValue
    : Awaited<TReturn> extends Response
      ? unknown
      : Awaited<TReturn>;

export type ApiMethod<TMethod> = TMethod extends (...args: infer TArgs) => infer TReturn
  ? (...args: TArgs) => Result<ReconciledReturn<TReturn>, Problem>
  : never;

/** Recursively maps a Kiota-shaped client while leaving non-client values untouched. */
export type ApiClient<TClient> = {
  readonly [TKey in keyof TClient]: TClient[TKey] extends (...args: infer _TArgs) => infer _TReturn
    ? ApiMethod<TClient[TKey]>
    : TClient[TKey] extends PromiseLike<unknown>
      ? TClient[TKey]
      : TClient[TKey] extends object
        ? ApiClient<TClient[TKey]>
        : TClient[TKey];
};

export interface ResolvedBackend {
  readonly coordinate: LpsmCoordinate;
  readonly key: LpsmKey;
  readonly baseUrl: string;
  readonly resourceKey: CanonicalResourceKey;
}

export interface ApiEngine {
  resolve<TClient extends object>(coordinate: LpsmCoordinate): Result<ApiClient<TClient>, Problem>;
  list(): readonly ResolvedBackend[];
}

export type ReconciliationPhase =
  | 'authentication'
  | 'configuration'
  | 'network'
  | 'timeout'
  | 'response-body'
  | 'upstream';

export interface ReconciliationContext {
  readonly backend: LpsmCoordinate;
  readonly backendKey: LpsmKey;
  readonly problems: ApiProblems;
}
