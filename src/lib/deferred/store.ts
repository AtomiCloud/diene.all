import type { Problem } from '@atomicloud/diene.problems';
import type { Result } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';

/**
 * Injectable clock. Domain time is always a {@link Temporal.Instant}; production
 * uses {@link systemClock} and tests inject a fake so no real time is read.
 */
export interface Clock {
  now(): Temporal.Instant;
}

/** The production clock — reads the real UTC instant. */
export const systemClock: Clock = {
  now: () => Temporal.Now.instant(),
};

/**
 * Lifecycle of a deferred app-handoff nonce (C0 §7).
 *
 * `active → claimed → consumed | revoked`. The `claimed` transition is
 * exclusive and never returns to `active`, including after a process crash —
 * this is what makes redeem replay-safe and fail-closed.
 */
export type NonceState = 'active' | 'claimed' | 'consumed' | 'revoked';

/**
 * The persisted record for a single deferred handoff nonce. The nonce itself is
 * the store key and is not part of the record (C0 §7 record shape:
 * `{ sub, email, expiresAt, state }`). `expiresAt` is a domain
 * {@link Temporal.Instant}; only adapters serialise it to a wire/RFC 3339 form.
 */
export interface DeferredNonceRecord {
  /** The validated OIDC `sub` of the minting web session (re-resolved at redeem, Q-I47). */
  readonly sub: string;
  /** The primary email captured at mint time, compared ASCII case-insensitively at redeem. */
  readonly email: string;
  /** Absolute expiry as a UTC instant. */
  readonly expiresAt: Temporal.Instant;
  /** Current lifecycle state. */
  readonly state: NonceState;
}

/**
 * Port for the deferred-handoff nonce store (C0 §7).
 *
 * Contract for every implementation (in-memory fake, Redis adapter):
 * - `create` persists a fresh `active` record under `nonce`, honouring the
 *   15-minute TTL carried by `record.expiresAt`; a second `create` for the same
 *   live nonce fails.
 * - `claim` atomically transitions exactly one unexpired `active` record to
 *   `claimed` and returns it. Every concurrent, replayed, expired, consumed,
 *   revoked, or missing attempt fails.
 * - `consume` transitions a `claimed` record to `consumed`.
 * - `revoke` transitions any live record to `revoked` (best-effort, idempotent).
 *
 * No-oracle rule: every failure resolves to the single generic
 * `AppHandoffExpired` problem — implementations MUST NOT distinguish missing,
 * expired, replayed, or infrastructure states in the returned problem. Callers
 * (redeem) re-map defensively regardless.
 */
export interface DeferredTokenStore {
  create(nonce: string, record: DeferredNonceRecord): Result<void, Problem>;
  claim(nonce: string): Result<DeferredNonceRecord, Problem>;
  consume(nonce: string): Result<void, Problem>;
  revoke(nonce: string): Result<void, Problem>;
}
