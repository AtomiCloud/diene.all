import type { Problem } from '@atomicloud/diene.problems';
import { Res, type Result, type ResultSerial } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import type { Claims } from './jwt';
import { type ExpiryOptions, isExpired } from './jwt';
import type { AuthClock } from './provider';
import type { CanonicalResourceKey } from './resource-tree';

export interface TokenSet {
  readonly idToken: string;
  readonly accessTokens: Readonly<Record<CanonicalResourceKey, string>>;
}

export type UserInfo = Readonly<Record<string, unknown>>;

export interface AllAuthState {
  readonly tokens: TokenSet;
  readonly claims: Claims;
  readonly user: UserInfo;
}

export type AuthData = TokenSet | Claims | UserInfo | AllAuthState;

export type AuthState<T extends AuthData> =
  | {
      readonly __kind: 'authed';
      readonly value: { readonly isAuthed: true; readonly data: T };
    }
  | {
      readonly __kind: 'unauthed';
      readonly value: { readonly isAuthed: false };
    };

export function authed<T extends AuthData>(data: T): AuthState<T> {
  return { __kind: 'authed', value: { isAuthed: true, data } };
}

export function unauthed<T extends AuthData>(): AuthState<T> {
  return { __kind: 'unauthed', value: { isAuthed: false } };
}

/** Default skew applied when deciding whether a cached token set needs a refresh. */
export const DEFAULT_REFRESH_SKEW = Temporal.Duration.from({ seconds: 30 });

/** The production clock — reads the real UTC instant. Tests inject a fake instead. */
export const systemClock: AuthClock = {
  now: () => Temporal.Now.instant(),
};

/**
 * Whether any token in the set is expired relative to the injected instant.
 * Malformed tokens propagate as a typed failure instead of being swallowed, so
 * a retriever caller fails closed on a real `Problem`.
 */
export function stateNeedRefresh(tokenSet: TokenSet, options: ExpiryOptions): Result<boolean, Problem> {
  const tokens = [tokenSet.idToken, ...Object.values(tokenSet.accessTokens)];
  return Res.all(...tokens.map(token => isExpired(token, options)))
    .map(flags => flags.some(Boolean))
    .mapErr(errors => (errors as Problem[])[0] as Problem);
}

/**
 * A single injected, mutable cell holding the most recent cached auth-state.
 * Retrievers hold the cell by a `readonly` reference and never carry mutable
 * state themselves, which keeps the service object stateless.
 */
export interface AuthStateCell<T extends AuthData> {
  peek(): AuthState<T> | undefined;
  write(state: AuthState<T>): void;
  clear(): void;
}

export function createAuthStateCell<T extends AuthData>(): AuthStateCell<T> {
  let slot: AuthState<T> | undefined;
  return {
    peek: () => slot,
    write: state => {
      slot = state;
    },
    clear: () => {
      slot = undefined;
    },
  };
}

/**
 * Coordinates a single in-flight token-set refresh so concurrent callers await
 * the same promise. Injected explicitly so the coordination state lives outside
 * the retriever object.
 */
export interface SingleFlightCell<T extends AuthData> {
  peek(): Promise<ResultSerial<AuthState<T>, Problem>> | undefined;
  begin(flight: Promise<ResultSerial<AuthState<T>, Problem>>): void;
  settle(flight: Promise<ResultSerial<AuthState<T>, Problem>>): void;
  clear(): void;
}

export function createSingleFlightCell<T extends AuthData>(): SingleFlightCell<T> {
  let current: Promise<ResultSerial<AuthState<T>, Problem>> | undefined;
  return {
    peek: () => current,
    begin: flight => {
      current = flight;
    },
    settle: flight => {
      if (current === flight) current = undefined;
    },
    clear: () => {
      current = undefined;
    },
  };
}

/** Portable auth-state seam consumed by API engines and frontend bindings. */
export interface IAuthStateRetriever {
  getTokenSet(): Result<AuthState<TokenSet>, Problem>;
  getClaims(): Result<AuthState<Claims>, Problem>;
  getUserInfo(): Result<AuthState<UserInfo>, Problem>;
  getStates(): Result<AuthState<AllAuthState>, Problem>;
  forceTokenSet(): Result<AuthState<TokenSet>, Problem>;
}
