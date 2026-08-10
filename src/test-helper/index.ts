import {
  type AllAuthState,
  type AuthState,
  authed,
  type CanonicalResourceKey,
  type Claims,
  canonicalResourceKey,
  type IAuthStateRetriever,
  type ResourceKey,
  type TokenSet,
  type UserInfo,
  unauthed,
} from '@atomicloud/diene.auth-engine';
import {
  createProblem,
  type ErrorPortalConfig,
  isProblem,
  type Problem,
  ProblemRegistry,
  type RegisteredProblem,
} from '@atomicloud/diene.problems';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type { z } from 'zod';

import { type ApiProblems, registerApiProblems } from '../lib/problems';

export const testPortal: ErrorPortalConfig = Object.freeze({
  scheme: 'https',
  host: 'errors.test.atomi.cloud',
  landscape: 'test',
  platform: 'test',
  service: 'api-engine',
  module: 'tests',
});

export interface ApiTestProblems {
  readonly registry: ProblemRegistry;
  readonly problems: ApiProblems;
}

export async function createApiTestProblems(portal: ErrorPortalConfig = testPortal): Promise<ApiTestProblems> {
  const registry = new ProblemRegistry(portal);
  const serial = await registerApiProblems(registry).serial();
  if (serial[0] === 'err') throw new Error(serial[1].detail ?? serial[1].title);
  return Object.freeze({ registry, problems: serial[1] });
}

export async function canonicalTestResource(resource: ResourceKey): Promise<CanonicalResourceKey> {
  const serial = await canonicalResourceKey(resource).serial();
  if (serial[0] === 'err') throw new Error(serial[1].detail ?? serial[1].title);
  return serial[1];
}

/** Mutable test state implementing the exact published auth-engine consumer seam. */
export class FakeAuthStateRetriever implements IAuthStateRetriever {
  tokenState: AuthState<TokenSet>;
  forcedTokenState: AuthState<TokenSet>;
  failure?: Problem;
  getCalls = 0;
  forceCalls = 0;

  constructor(tokenState: AuthState<TokenSet>, forcedTokenState: AuthState<TokenSet> = tokenState) {
    this.tokenState = tokenState;
    this.forcedTokenState = forcedTokenState;
  }

  getTokenSet(): Result<AuthState<TokenSet>, Problem> {
    this.getCalls += 1;
    return this.failure === undefined ? Ok(this.tokenState) : Err(this.failure);
  }

  forceTokenSet(): Result<AuthState<TokenSet>, Problem> {
    this.forceCalls += 1;
    return this.failure === undefined ? Ok(this.forcedTokenState) : Err(this.failure);
  }

  getClaims(): Result<AuthState<Claims>, Problem> {
    return Ok(unauthed<Claims>());
  }

  getUserInfo(): Result<AuthState<UserInfo>, Problem> {
    return Ok(unauthed<UserInfo>());
  }

  getStates(): Result<AuthState<AllAuthState>, Problem> {
    return Ok(unauthed<AllAuthState>());
  }
}

export function fakeAuthed(tokens: Readonly<Record<CanonicalResourceKey, string>>): FakeAuthStateRetriever {
  return new FakeAuthStateRetriever(
    authed<TokenSet>({ idToken: 'test-id-token', accessTokens: Object.freeze({ ...tokens }) }),
  );
}

export function fakeUnauthed(forced: Readonly<Record<CanonicalResourceKey, string>> = {}): FakeAuthStateRetriever {
  return new FakeAuthStateRetriever(
    unauthed<TokenSet>(),
    Object.keys(forced).length === 0
      ? unauthed<TokenSet>()
      : authed<TokenSet>({ idToken: 'forced-id-token', accessTokens: forced }),
  );
}

export type ScriptedOutcome =
  | { readonly kind: 'return'; readonly value: unknown }
  | { readonly kind: 'resolve'; readonly value: unknown }
  | { readonly kind: 'throw'; readonly error: unknown }
  | { readonly kind: 'reject'; readonly error: unknown };

export interface ScriptedCall {
  readonly method: string;
  readonly owner: object;
  readonly args: readonly unknown[];
}

export class ScriptedBackend {
  readonly calls: ScriptedCall[] = [];
  readonly #script: Map<string, ScriptedOutcome[]>;

  constructor(script: Readonly<Record<string, readonly ScriptedOutcome[]>>) {
    this.#script = new Map(Object.entries(script).map(([method, outcomes]) => [method, [...outcomes]]));
  }

  invoke(method: string, owner: object, args: readonly unknown[]): unknown {
    this.calls.push(Object.freeze({ method, owner, args: Object.freeze([...args]) }));
    const outcome = this.#script.get(method)?.shift();
    if (outcome === undefined) throw new Error(`No scripted outcome remains for ${method}.`);
    switch (outcome.kind) {
      case 'return':
        return outcome.value;
      case 'resolve':
        return Promise.resolve(outcome.value);
      case 'throw':
        throw outcome.error;
      case 'reject':
        return Promise.reject(outcome.error);
    }
  }
}

export interface ScriptedKiotaClient {
  readonly client: {
    readonly marker: 'root';
    root(value?: unknown): unknown;
    readonly nested: {
      readonly marker: 'nested';
      call(value?: unknown): unknown;
    };
    readonly promisedNamespace: Promise<{ readonly untouched: true }>;
  };
  readonly backend: ScriptedBackend;
}

/** Kiota-shaped fake: callable root, nested request builder, and a Promise-valued property. */
export function createScriptedKiotaClient(
  script: Readonly<Record<string, readonly ScriptedOutcome[]>>,
): ScriptedKiotaClient {
  const backend = new ScriptedBackend(script);
  const nested = {
    marker: 'nested' as const,
    call(this: object, value?: unknown) {
      return backend.invoke('nested.call', this, [value]);
    },
  };
  const client = {
    marker: 'root' as const,
    root(this: object, value?: unknown) {
      return backend.invoke('root', this, [value]);
    },
    nested,
    promisedNamespace: Promise.resolve({ untouched: true as const }),
  };
  return Object.freeze({ client, backend });
}

export function jsonResponse(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

export function textResponse(value: string, status = 200): Response {
  return new Response(value, { status, headers: { 'content-type': 'text/plain' } });
}

export function statusOnlyResponse(status: number): Response {
  return new Response(null, { status });
}

export function unreadableResponse(status = 502, json = true): Response {
  const stream = new ReadableStream({
    start(controller) {
      controller.error(new Error('scripted body read failure'));
    },
  });
  return new Response(stream, {
    status,
    headers: json ? { 'content-type': 'application/json' } : undefined,
  });
}

export function problemFixture<TSchema extends z.ZodType>(
  definition: RegisteredProblem<TSchema>,
  data: z.input<TSchema>,
  detail = 'Scripted problem',
): Problem<z.output<TSchema>> {
  return createProblem(definition, { detail, data });
}

export function problemResponse(problem: Problem, status = problem.status): Response {
  return new Response(JSON.stringify(problem), {
    status,
    headers: { 'content-type': 'application/problem+json' },
  });
}

export function assertProblem(value: unknown, expectedType?: string): asserts value is Problem {
  if (!isProblem(value)) throw new Error('Expected a diene.problems-compatible Problem.');
  if (expectedType !== undefined && value.type !== expectedType) {
    throw new Error(`Expected Problem type ${expectedType}, received ${value.type}.`);
  }
}

export function assertResultSerial<T>(
  serial: readonly ['ok', T] | readonly ['err', Problem],
  variant: 'ok' | 'err',
): void {
  if (serial[0] !== variant) {
    throw new Error(`Expected ${variant} Result, received ${serial[0]}.`);
  }
}
