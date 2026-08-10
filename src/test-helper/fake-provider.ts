import { isProblem, type Problem } from '@atomicloud/diene.problems';
import { Err, Ok, Res, type Result } from '@atomicloud/diene.result';
import type { AuthProvider, SignInUrlOptions, TokenResponse } from '../lib/provider';

export type ProviderScriptStep<T> = T | Problem | (() => T | Problem | Promise<T | Problem>);

export interface FakeAuthProviderOptions {
  readonly idToken?: string;
  readonly accessTokens?: Readonly<Record<string, TokenResponse>>;
  readonly signInUrl?: string;
  readonly mapError?: (error: unknown) => Problem;
}

function defaultProblem(error: unknown): Problem {
  return {
    type: 'about:blank',
    title: 'Fake provider failure',
    status: 500,
    detail: error instanceof Error ? error.message : String(error),
    data: {},
  };
}

function runProviderStep<T>(
  step: ProviderScriptStep<T> | undefined,
  missing: string | undefined,
  fallback: T | undefined,
  mapError: (error: unknown) => Problem,
): Result<T, Problem> {
  return Res.async<T, Problem>(async () => {
    try {
      if (step === undefined) {
        if (missing !== undefined) return Err<T, Problem>(mapError(new Error(missing)));
        return Ok<T, Problem>(fallback as T);
      }
      const value = typeof step === 'function' ? await (step as () => T | Problem | Promise<T | Problem>)() : step;
      return isProblem(value) ? Err<T, Problem>(value) : Ok<T, Problem>(value);
    } catch (error: unknown) {
      return Err<T, Problem>(mapError(error));
    }
  });
}

export class FakeAuthProvider implements AuthProvider {
  readonly accessTokenCalls: string[] = [];
  readonly signInCalls: SignInUrlOptions[] = [];
  refreshCalls = 0;
  idTokenCalls = 0;
  clearTokenCalls = 0;
  readonly #accessTokens = new Map<string, TokenResponse>();
  readonly #accessScripts = new Map<string, ProviderScriptStep<TokenResponse>[]>();
  readonly #refreshScript: ProviderScriptStep<void>[] = [];
  readonly #idTokenScript: ProviderScriptStep<string>[] = [];
  readonly #clearScript: ProviderScriptStep<void>[] = [];
  readonly #mapError: (error: unknown) => Problem;
  #idToken: string;
  #signInUrl: string;

  constructor(options: FakeAuthProviderOptions = {}) {
    this.#idToken = options.idToken ?? '';
    this.#signInUrl = options.signInUrl ?? 'https://identity.invalid/oidc/auth';
    this.#mapError = options.mapError ?? defaultProblem;
    for (const [resource, token] of Object.entries(options.accessTokens ?? {})) {
      this.#accessTokens.set(resource, token);
    }
  }

  setIdToken(token: string): void {
    this.#idToken = token;
  }

  setAccessToken(resource: string, token: TokenResponse): void {
    this.#accessTokens.set(resource, token);
  }

  enqueueAccessToken(resource: string, ...steps: ProviderScriptStep<TokenResponse>[]): void {
    const script = this.#accessScripts.get(resource) ?? [];
    script.push(...steps);
    this.#accessScripts.set(resource, script);
  }

  enqueueRefresh(...steps: ProviderScriptStep<void>[]): void {
    this.#refreshScript.push(...steps);
  }

  enqueueIdToken(...steps: ProviderScriptStep<string>[]): void {
    this.#idTokenScript.push(...steps);
  }

  enqueueClear(...steps: ProviderScriptStep<void>[]): void {
    this.#clearScript.push(...steps);
  }

  getAccessToken(resource: string): Result<TokenResponse, Problem> {
    this.accessTokenCalls.push(resource);
    const step = this.#accessScripts.get(resource)?.shift() ?? this.#accessTokens.get(resource);
    return runProviderStep(step, `No access token scripted for ${resource}`, undefined, this.#mapError);
  }

  refresh(): Result<void, Problem> {
    this.refreshCalls += 1;
    return runProviderStep(this.#refreshScript.shift() ?? undefined, undefined, undefined, this.#mapError);
  }

  getIdToken(): Result<string, Problem> {
    this.idTokenCalls += 1;
    return runProviderStep(
      this.#idTokenScript.shift() ?? this.#idToken,
      'No ID token scripted',
      undefined,
      this.#mapError,
    );
  }

  signInUrl(options: SignInUrlOptions): Result<string, Problem> {
    this.signInCalls.push(options);
    return Ok(this.#signInUrl);
  }

  clearTokens(): Result<void, Problem> {
    this.clearTokenCalls += 1;
    return runProviderStep(this.#clearScript.shift() ?? undefined, undefined, undefined, this.#mapError);
  }
}
