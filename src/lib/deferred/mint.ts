import type { Problem } from '@atomicloud/diene.problems';
import { Err, type Result } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import { z } from 'zod';
import { type AuthProblems, createAuthRefreshFailed, createUnauthorized } from '../problems';
import { type Clock, type DeferredNonceRecord, type DeferredTokenStore, systemClock } from './store';

/** Fixed deferred-handoff nonce TTL (C0 §7): 15 minutes. Not a config knob. */
export const DEFERRED_NONCE_TTL = Temporal.Duration.from({ minutes: 15 });

/** A deferred nonce is 32 cryptographically-random bytes (base64url → 43 chars). */
export const DEFERRED_NONCE_BYTE_LENGTH = 32;

/** The validated web session the mint reads `sub` and `email` from — never client input. */
export interface DeferredSession {
  readonly sub: string;
  readonly email: string;
}

/** Dependencies for {@link mintDeferredToken}. `clock`/`randomBytes` are injectable for tests. */
export interface MintDeferredTokenDeps {
  readonly store: DeferredTokenStore;
  readonly problems: Pick<AuthProblems, 'AuthRefreshFailed' | 'Unauthorized'>;
  readonly clock?: Clock;
  readonly randomBytes?: (length: number) => Uint8Array;
}

/** Successful mint result — the opaque nonce and its absolute expiry instant. */
export interface DeferredMintResult {
  readonly nonce: string;
  readonly expiresAt: Temporal.Instant;
}

function defaultRandomBytes(length: number): Uint8Array {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return bytes;
}

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** Runtime shape guard for the session — never throws on malformed input (M33). */
const sessionSchema = z.object({
  sub: z.string(),
  email: z.string(),
});

/**
 * Mint a deferred app-handoff nonce (C0 §7 mint half).
 *
 * `sub`/`email` come from the already-validated web session; the session is
 * `safeParse`d (never throws on malformed runtime values) and blank values are
 * rejected before any store hit (M33) with a generic `Unauthorized`. The nonce
 * is 32 crypto-random bytes encoded base64url without padding (43 chars), TTL
 * fixed at 15 minutes. No Logto token is minted here — that happens at redeem.
 */
export function mintDeferredToken(
  session: DeferredSession,
  deps: MintDeferredTokenDeps,
): Result<DeferredMintResult, Problem> {
  const invalidSession = (): Result<DeferredMintResult, Problem> =>
    Err(createUnauthorized(deps.problems, 'A valid authenticated session is required to mint a deferred handoff.'));

  const parsedSession = sessionSchema.safeParse(session);
  if (!parsedSession.success) {
    return invalidSession();
  }
  const sub = parsedSession.data.sub.trim();
  const email = parsedSession.data.email.trim();
  if (sub === '' || email === '') {
    return invalidSession();
  }

  const clock = deps.clock ?? systemClock;
  const randomBytes = deps.randomBytes ?? defaultRandomBytes;
  try {
    const bytes = randomBytes(DEFERRED_NONCE_BYTE_LENGTH);
    if (!(bytes instanceof Uint8Array) || bytes.length !== DEFERRED_NONCE_BYTE_LENGTH) {
      return Err(
        createAuthRefreshFailed(
          deps.problems,
          'The deferred handoff nonce generator returned an invalid byte sequence.',
        ),
      );
    }
    const nonce = bytesToBase64Url(bytes);
    const expiresAt = clock.now().add(DEFERRED_NONCE_TTL);
    const record: DeferredNonceRecord = { sub, email, expiresAt, state: 'active' };

    return deps.store.create(nonce, record).map(() => ({ nonce, expiresAt }));
  } catch {
    return Err(createAuthRefreshFailed(deps.problems, 'The deferred handoff nonce could not be minted.'));
  }
}
