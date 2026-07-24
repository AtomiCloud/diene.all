import type { Problem } from '@atomicloud/diene.problems';
import { Err, Ok, Res, type Result } from '@atomicloud/diene.result';
import { z } from 'zod';
import { type AuthProblems, createAppHandoffExpired } from '../problems';
import type { DeferredTokenStore } from './store';

/** Fixed Logto one-time-token lifetime at redeem (C0 §7): 120 seconds, not a ceiling. */
export const ONE_TIME_TOKEN_EXPIRES_IN_SECONDS = 120;

/** The Logto interaction event a redeem one-time token is minted for. */
export const REDEEM_INTERACTION_EVENT = 'SignIn';

/** A user account as read from the Logto Management API at redeem time (Q-I47). */
export interface LogtoUserAccount {
  readonly isSuspended: boolean;
  readonly primaryEmail: string | null;
}

/** A freshly minted Logto one-time token. */
export interface OneTimeToken {
  readonly token: string;
}

/**
 * Port the redeem flow uses to reach Logto (implemented by the Management API
 * adapter). Both methods return `Ok` only on a definitive success; every 404,
 * suspension read, upstream error, or transport failure is an `Err` — the redeem
 * flow collapses all of them to the single generic problem, so the specific
 * problem carried here is internal (log-only) detail.
 */
export interface DeferredIdentityClient {
  /** Resolve the minting `sub`. `Ok` only on `200`; `404`/error → `Err`. */
  getUser(sub: string): Result<LogtoUserAccount, Problem>;
  /** Mint a `SignIn` one-time token for `email` with a fixed 120s lifetime. */
  mintOneTimeToken(email: string): Result<OneTimeToken, Problem>;
}

/** Dependencies for {@link exchangeDeferredToken}. */
export interface ExchangeDeferredTokenDeps {
  readonly store: DeferredTokenStore;
  readonly identity: DeferredIdentityClient;
  readonly problems: Pick<AuthProblems, 'AppHandoffExpired'>;
}

/** Successful redeem result — the wire shape returned to the mobile client (C0 §7). */
export interface DeferredRedeemResult {
  readonly token: string;
  readonly email: string;
  readonly expiresIn: number;
}

/** Redeem device telemetry — parsed but MUST NOT affect identity or authorization. */
const deviceSchema = z
  .object({
    platform: z.enum(['android', 'ios']),
    appVersion: z.string().optional(),
    osVersion: z.string().optional(),
    model: z.string().optional(),
  })
  .strict();

/** Strict redeem input schema — unknown top-level or device keys are rejected (C0 §7). */
const redeemSchema = z
  .object({
    nonce: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
    device: deviceSchema.optional(),
  })
  .strict();

/** ASCII-only lowercasing for the case-insensitive email comparison (C0 §7). */
function asciiLower(value: string): string {
  let out = '';
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    out += String.fromCharCode(code >= 65 && code <= 90 ? code + 32 : code);
  }
  return out;
}

function emailMatches(current: string | null, expected: string): boolean {
  return current !== null && asciiLower(current) === asciiLower(expected);
}

/**
 * Redeem a deferred app-handoff nonce for a Logto one-time token (C0 §7 redeem half).
 *
 * Steps, all collapsing to one no-oracle `AppHandoffExpired` on any failure:
 *  1. strict-parse the redeem input (unknown keys and blank nonce rejected
 *     before any store hit, M33);
 *  2. atomically `claim` the nonce (`active → claimed`); every concurrent,
 *     replayed, expired, or malformed attempt fails identically;
 *  3. one `GET /api/users/{sub}` (Q-I47): require `200`, `isSuspended == false`,
 *     non-null `primaryEmail` equal to the stored mint-time email
 *     (ASCII case-insensitive) — any failure revokes and returns generic;
 *  4. mint `{ email, expiresIn: 120, context: { interactionEvent: "SignIn" } }`;
 *     failure revokes and returns generic;
 *  5. mark `consumed` before replying — a crash after claim is fail-closed and
 *     never mints a second token.
 */
export function exchangeDeferredToken(
  rawInput: unknown,
  deps: ExchangeDeferredTokenDeps,
): Result<DeferredRedeemResult, Problem> {
  const generic = (): Problem => createAppHandoffExpired(deps.problems);

  const parsed = redeemSchema.safeParse(rawInput);
  if (!parsed.success) {
    return Err(generic());
  }
  const nonce = parsed.data.nonce;

  return Res.async<DeferredRedeemResult, Problem>(async () => {
    const claim = deps.store.claim(nonce);
    if (!(await claim.isOk())) {
      // The nonce was never claimed by us — nothing to revoke.
      return Err(generic());
    }
    const record = await claim.unwrap();

    // Any post-claim failure revokes the nonce (best-effort) and returns generic.
    const revokeAndFail = async (): Promise<Result<DeferredRedeemResult, Problem>> => {
      await deps.store.revoke(nonce).serial();
      return Err(generic());
    };

    const userLookup = deps.identity.getUser(record.sub);
    if (!(await userLookup.isOk())) {
      return revokeAndFail();
    }
    const account = await userLookup.unwrap();
    if (account.isSuspended || !emailMatches(account.primaryEmail, record.email)) {
      return revokeAndFail();
    }
    const currentEmail = account.primaryEmail as string;

    const minted = deps.identity.mintOneTimeToken(currentEmail);
    if (!(await minted.isOk())) {
      return revokeAndFail();
    }
    const token = (await minted.unwrap()).token;

    // Mark consumed BEFORE replying; if this fails the nonce stays `claimed`
    // (never re-enters `active`), so a retry can never mint a second token.
    const consumed = deps.store.consume(nonce);
    if (!(await consumed.isOk())) {
      return Err(generic());
    }

    return Ok({ token, email: currentEmail, expiresIn: ONE_TIME_TOKEN_EXPIRES_IN_SECONDS });
  });
}
