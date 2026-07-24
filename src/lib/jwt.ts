import type { Problem, RegisteredProblem } from '@atomicloud/diene.problems';
import { createProblem, Unauthorized } from '@atomicloud/diene.problems';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import { decodeJwt } from 'jose';
import { z } from 'zod';

/** Portable JWT claims shape; keeps the public declarations independent of jose's ESM-only types. */
export type Claims = Readonly<Record<string, unknown>> &
  Readonly<{
    iss?: string;
    sub?: string;
    aud?: string | readonly string[];
    jti?: string;
    nbf?: number;
    exp?: number;
    iat?: number;
  }>;

type UnauthorizedProblem = RegisteredProblem<typeof Unauthorized.dataSchema>;

/** Default clock skew tolerated when deciding whether a token is expired. */
export const DEFAULT_EXPIRY_SKEW = Temporal.Duration.from({ seconds: 30 });

/** Expiry-check inputs; the instant is always injected so no wall clock is read implicitly. */
export interface ExpiryOptions {
  readonly skew?: Temporal.Duration;
  readonly now: Temporal.Instant;
}

/** External inputs are validated before use so malformed or blank values fail explicitly. */
const tokenSchema = z.string().min(1);
const identifierSchema = z.string().trim().min(1);
const temporalInstantSchema = z.custom<Temporal.Instant>(value => value instanceof Temporal.Instant);
const nonNegativeTimeDurationSchema = z
  .custom<Temporal.Duration>(value => value instanceof Temporal.Duration)
  .refine(value => {
    try {
      const reference = Temporal.Instant.from('2000-01-01T00:00:00Z');
      return Temporal.Instant.compare(reference.subtract(value), reference) <= 0;
    } catch {
      return false;
    }
  });
const expiryOptionsSchema = z
  .object({
    skew: nonNegativeTimeDurationSchema.optional(),
    now: temporalInstantSchema,
  })
  .strict();
const numericDateSchema = z.number().finite().min(-8_640_000_000_000).max(8_640_000_000_000);

function invalidTokenProblem(unauthorized?: UnauthorizedProblem): Problem {
  if (unauthorized !== undefined) {
    return createProblem(unauthorized, {
      detail: 'The token is malformed.',
      data: { reason: 'invalid_token' },
    });
  }

  return {
    type: 'about:blank',
    title: Unauthorized.title,
    status: Unauthorized.status,
    detail: 'The token is malformed.',
    data: { reason: 'invalid_token' },
  };
}

function blankInputProblem(field: string): Problem {
  return {
    type: 'about:blank',
    title: 'Invalid claim reference',
    status: 400,
    detail: `The ${field} must be a non-empty value.`,
    data: { reason: `blank_${field}` },
  };
}

export function decodeToken(token: string, unauthorized?: UnauthorizedProblem): Result<Claims, Problem> {
  const parsed = tokenSchema.safeParse(token);
  if (!parsed.success) return Err(invalidTokenProblem(unauthorized));
  try {
    return Ok(decodeJwt(parsed.data) as Claims);
  } catch {
    return Err(invalidTokenProblem(unauthorized));
  }
}

/**
 * Whether the token is expired relative to the injected instant. Malformed
 * tokens are an explicit typed failure so callers fail closed on a real
 * `Problem` rather than a silently coerced boolean.
 */
export function isExpired(
  token: string,
  options: ExpiryOptions,
  unauthorized?: UnauthorizedProblem,
): Result<boolean, Problem> {
  const parsedOptions = expiryOptionsSchema.safeParse(options);
  if (!parsedOptions.success) return Err(blankInputProblem('expiry options'));
  const skew = parsedOptions.data.skew ?? DEFAULT_EXPIRY_SKEW;
  const now = parsedOptions.data.now;
  return decodeToken(token, unauthorized).andThen(claims => {
    const exp = claims.exp;
    if (exp === undefined) return Ok(false);
    const parsedExp = numericDateSchema.safeParse(exp);
    if (!parsedExp.success) return Err(invalidTokenProblem(unauthorized));
    try {
      const threshold = Temporal.Instant.fromEpochMilliseconds(Math.round(parsedExp.data * 1_000)).subtract(skew);
      return Ok(Temporal.Instant.compare(now, threshold) >= 0);
    } catch {
      return Err(blankInputProblem('expiry options'));
    }
  });
}

/**
 * Read a single claim. A malformed token or a blank claim key is an explicit
 * typed failure; an absent claim resolves to `Ok(undefined)`.
 */
export function claim<T>(
  token: string,
  key: string,
  unauthorized?: UnauthorizedProblem,
): Result<T | undefined, Problem> {
  const parsedKey = identifierSchema.safeParse(key);
  if (!parsedKey.success) return Err(blankInputProblem('claim key'));
  return decodeToken(token, unauthorized).map(claims => claims[parsedKey.data] as T | undefined);
}

/** Derive the `<platform>_<service>` registration claim key; blank inputs fail explicitly. */
export function registrationClaimKey(platform: string, service: string): Result<string, Problem> {
  const parsedPlatform = identifierSchema.safeParse(platform);
  if (!parsedPlatform.success) return Err(blankInputProblem('platform'));
  const parsedService = identifierSchema.safeParse(service);
  if (!parsedService.success) return Err(blankInputProblem('service'));
  return Ok(`${parsedPlatform.data}_${parsedService.data}`.toLowerCase().replaceAll('-', '_'));
}

/**
 * Whether the exact `"true"` registration claim (C0 §8 S20) is present. Blank
 * platform/service and malformed tokens surface as typed failures.
 */
export function hasRegistrationClaim(
  token: string,
  platform: string,
  service: string,
  unauthorized?: UnauthorizedProblem,
): Result<boolean, Problem> {
  return registrationClaimKey(platform, service)
    .andThen(key => claim<unknown>(token, key, unauthorized))
    .map(value => value === 'true');
}
