import type { Problem } from '@atomicloud/diene.problems';
import type { Result } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';

export const ACCESS_TOKEN_LIFETIME = Temporal.Duration.from({ minutes: 10 });
export const REFRESH_TOKEN_LIFETIME = Temporal.Duration.from({ days: 14 });

export interface AuthClock {
  now(): Temporal.Instant;
}

export interface TokenResponse {
  readonly token: string;
  readonly expiresAt: Temporal.Instant;
}

export interface SignInUrlOptions {
  readonly redirectUri: string;
  readonly state: string;
  readonly codeChallenge: string;
  readonly scopes?: readonly string[];
  readonly resources?: readonly string[];
  readonly prompt?: string;
  readonly extraParameters?: Readonly<Record<string, string>>;
}

/** Identity-provider boundary used by server and edge auth machinery. */
export interface AuthProvider {
  getAccessToken(resource: string): Result<TokenResponse, Problem>;
  refresh(): Result<void, Problem>;
  getIdToken(): Result<string, Problem>;
  signInUrl(options: SignInUrlOptions): Result<string, Problem>;
  clearTokens(): Result<void, Problem>;
}
