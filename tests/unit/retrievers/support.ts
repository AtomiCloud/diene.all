import type { Problem } from '@atomicloud/diene.problems';
import { Ok, type Result } from '@atomicloud/diene.result';
import type { AuthState, UserInfo } from '../../../src/lib/retriever';
import type { FetchLike } from '../../../src/lib/retrievers/client';
import type { AuthSessionAccessor } from '../../../src/lib/retrievers/server';

/** A fetch stub that returns a JSON body per endpoint and records call counts. */
export interface StubFetch {
  readonly fetch: FetchLike;
  readonly calls: Record<string, number>;
}

export function stubFetch(bodies: Readonly<Record<string, unknown>>): StubFetch {
  const calls: Record<string, number> = {};
  const fetch: FetchLike = input => {
    const url = String(input);
    calls[url] = (calls[url] ?? 0) + 1;
    const body = bodies[url];
    return Promise.resolve(
      new Response(JSON.stringify(body ?? null), { headers: { 'content-type': 'application/json' } }),
    );
  };
  return { fetch, calls };
}

/** Serialise a state as the endpoint's `Ok` wire shape (`['ok', state]`). */
export function okBody<T>(state: T): readonly ['ok', T] {
  return ['ok', state] as const;
}

/** A scripted {@link AuthSessionAccessor} for the server retriever. */
export class FakeSession implements AuthSessionAccessor {
  isAuthenticatedCalls = 0;
  #authenticated: boolean;
  #userInfo: Result<UserInfo, Problem>;

  constructor(options: { authenticated?: boolean; userInfo?: UserInfo } = {}) {
    this.#authenticated = options.authenticated ?? true;
    this.#userInfo = Ok(options.userInfo ?? {});
  }

  setAuthenticated(authenticated: boolean): void {
    this.#authenticated = authenticated;
  }

  isAuthenticated(): boolean {
    this.isAuthenticatedCalls += 1;
    return this.#authenticated;
  }

  getUserInfo(): Result<UserInfo, Problem> {
    return this.#userInfo;
  }
}

export type { AuthState };
