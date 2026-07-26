import type { Problem } from '@atomicloud/diene.problems';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type { Claims } from '../lib/jwt';
import {
  type AllAuthState,
  type AuthState,
  authed,
  type IAuthStateRetriever,
  type TokenSet,
  type UserInfo,
  unauthed,
} from '../lib/retriever';

export interface FakeRetrieverOptions {
  readonly authenticated?: boolean;
  readonly tokenSet?: TokenSet;
  readonly claims?: Claims;
  readonly userInfo?: UserInfo;
  readonly problem?: Problem;
}

function fakeRetrieverState<T extends TokenSet | Claims | UserInfo>(
  authenticated: boolean,
  problem: Problem | undefined,
  data: T,
): Result<AuthState<T>, Problem> {
  if (problem !== undefined) return Err(problem);
  return Ok(authenticated ? authed(data) : unauthed<T>());
}

export class FakeAuthStateRetriever implements IAuthStateRetriever {
  getTokenSetCalls = 0;
  getClaimsCalls = 0;
  getUserInfoCalls = 0;
  getStatesCalls = 0;
  forceTokenSetCalls = 0;
  readonly #forced: (TokenSet | Problem | 'unauthed')[] = [];
  #authenticated: boolean;
  #tokenSet: TokenSet;
  #claims: Claims;
  #userInfo: UserInfo;
  #problem?: Problem;

  constructor(options: FakeRetrieverOptions = {}) {
    this.#authenticated = options.authenticated ?? true;
    this.#tokenSet = options.tokenSet ?? { idToken: '', accessTokens: {} };
    this.#claims = options.claims ?? {};
    this.#userInfo = options.userInfo ?? {};
    this.#problem = options.problem;
  }

  setAuthenticated(authenticated: boolean): void {
    this.#authenticated = authenticated;
  }

  setTokenSet(tokenSet: TokenSet): void {
    this.#tokenSet = tokenSet;
  }

  setProblem(problem?: Problem): void {
    this.#problem = problem;
  }

  enqueueForced(...steps: (TokenSet | Problem | 'unauthed')[]): void {
    this.#forced.push(...steps);
  }

  getTokenSet(): Result<AuthState<TokenSet>, Problem> {
    this.getTokenSetCalls += 1;
    return fakeRetrieverState(this.#authenticated, this.#problem, this.#tokenSet);
  }

  getClaims(): Result<AuthState<Claims>, Problem> {
    this.getClaimsCalls += 1;
    return fakeRetrieverState(this.#authenticated, this.#problem, this.#claims);
  }

  getUserInfo(): Result<AuthState<UserInfo>, Problem> {
    this.getUserInfoCalls += 1;
    return fakeRetrieverState(this.#authenticated, this.#problem, this.#userInfo);
  }

  getStates(): Result<AuthState<AllAuthState>, Problem> {
    this.getStatesCalls += 1;
    if (this.#problem !== undefined) return Err(this.#problem);
    if (!this.#authenticated) return Ok(unauthed<AllAuthState>());
    return Ok(authed({ tokens: this.#tokenSet, claims: this.#claims, user: this.#userInfo }));
  }

  forceTokenSet(): Result<AuthState<TokenSet>, Problem> {
    this.forceTokenSetCalls += 1;
    const step = this.#forced.shift();
    if (step === 'unauthed') return Ok(unauthed<TokenSet>());
    if (step !== undefined && 'status' in step) return Err(step);
    if (step !== undefined) this.#tokenSet = step;
    return fakeRetrieverState(this.#authenticated, this.#problem, this.#tokenSet);
  }
}

export class FakeClientAuthStateRetriever extends FakeAuthStateRetriever {}
export class FakeServerAuthStateRetriever extends FakeAuthStateRetriever {}
