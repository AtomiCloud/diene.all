import { createProblem, type Problem, type ProblemInit, type RegisteredProblem } from '@atomicloud/diene.problems';
import { Temporal } from '@js-temporal/polyfill';
import type { z } from 'zod';
import type { DeferredNonceRecord } from '../lib/deferred/store';
import type { Claims } from '../lib/jwt';
import type { CanonicalResourceKey } from '../lib/resource-tree';
import type { TokenSet } from '../lib/retriever';

const DEFAULT_DEFERRED_EXPIRY = Temporal.Instant.from('2099-01-01T00:15:00Z');

function base64UrlJson(value: unknown): string {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

export function buildUnsignedJwt(claims: Claims = {}, header: Readonly<Record<string, unknown>> = {}): string {
  return `${base64UrlJson({ alg: 'none', typ: 'JWT', ...header })}.${base64UrlJson(claims)}.`;
}

export function buildClaims(overrides: Claims = {}): Claims {
  return Object.freeze({ sub: 'test-user', email: 'test@example.invalid', ...overrides });
}

export interface TokenSetBuilderOptions {
  readonly idTokenClaims?: Claims;
  readonly accessTokenClaims?: Readonly<Record<CanonicalResourceKey, Claims>>;
}

export function buildTokenSet(options: TokenSetBuilderOptions = {}): TokenSet {
  return Object.freeze({
    idToken: buildUnsignedJwt(options.idTokenClaims ?? buildClaims()),
    accessTokens: Object.freeze(
      Object.fromEntries(
        Object.entries(options.accessTokenClaims ?? {}).map(([key, claims]) => [key, buildUnsignedJwt(claims)]),
      ),
    ) as Record<CanonicalResourceKey, string>,
  });
}

export function buildDeferredNonceRecord(overrides: Partial<DeferredNonceRecord> = {}): DeferredNonceRecord {
  return Object.freeze({
    sub: 'test-user',
    email: 'test@example.invalid',
    expiresAt: DEFAULT_DEFERRED_EXPIRY,
    state: 'active',
    ...overrides,
  });
}

export function buildProblemFixture<TSchema extends z.ZodType>(
  problem: RegisteredProblem<TSchema>,
  init: ProblemInit<z.input<TSchema>>,
): Problem<z.output<TSchema>> {
  return createProblem(problem, init);
}
