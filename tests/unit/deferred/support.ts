import type { Problem } from '@atomicloud/diene.problems';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import type { DeferredIdentityClient, LogtoUserAccount, OneTimeToken } from '../../../src/lib/deferred/exchange';
import {
  type Clock,
  type DeferredNonceRecord,
  type DeferredTokenStore,
  systemClock,
} from '../../../src/lib/deferred/store';
import { createAppHandoffExpired } from '../../../src/lib/problems';
import { testAuthProblems } from '../../support/auth-problems';

export { testAuthProblems };

const PROBLEMS = testAuthProblems();

export function genericExpiry(): Problem {
  return createAppHandoffExpired(PROBLEMS);
}

/** A deterministic {@link Clock} for tests — no real time is read. */
export class FakeClock implements Clock {
  #instant: Temporal.Instant;

  constructor(start: Temporal.Instant) {
    this.#instant = start;
  }

  now(): Temporal.Instant {
    return this.#instant;
  }

  /** Move the clock forward by a duration. */
  advance(duration: Temporal.Duration): void {
    this.#instant = this.#instant.add(duration);
  }
}

function isExpired(record: DeferredNonceRecord, clock: Clock): boolean {
  return Temporal.Instant.compare(record.expiresAt, clock.now()) <= 0;
}

/**
 * In-memory reference {@link DeferredTokenStore}. Honours the full C0 §7
 * lifecycle against an injected {@link Clock}, so TTL behaviour is proven with a
 * fake clock rather than real waits.
 */
export class InMemoryDeferredStore implements DeferredTokenStore {
  readonly #records = new Map<string, DeferredNonceRecord>();
  readonly #clock: Clock;

  constructor(clock: Clock = systemClock) {
    this.#clock = clock;
  }

  create(nonce: string, record: DeferredNonceRecord): Result<void, Problem> {
    const existing = this.#records.get(nonce);
    if (existing !== undefined && !isExpired(existing, this.#clock)) {
      return Err(genericExpiry());
    }
    if (isExpired(record, this.#clock)) return Err(genericExpiry());
    if (existing !== undefined) this.#records.delete(nonce);
    this.#records.set(nonce, { ...record, state: 'active' });
    return Ok(undefined);
  }

  claim(nonce: string): Result<DeferredNonceRecord, Problem> {
    const record = this.#records.get(nonce);
    if (record === undefined || record.state !== 'active' || isExpired(record, this.#clock)) {
      return Err(genericExpiry());
    }
    const claimed: DeferredNonceRecord = { ...record, state: 'claimed' };
    this.#records.set(nonce, claimed);
    return Ok(claimed);
  }

  consume(nonce: string): Result<void, Problem> {
    const record = this.#records.get(nonce);
    if (record === undefined || record.state !== 'claimed' || isExpired(record, this.#clock)) {
      return Err(genericExpiry());
    }
    this.#records.set(nonce, { ...record, state: 'consumed' });
    return Ok(undefined);
  }

  revoke(nonce: string): Result<void, Problem> {
    const record = this.#records.get(nonce);
    if (record === undefined || isExpired(record, this.#clock)) {
      return Err(genericExpiry());
    }
    this.#records.set(nonce, { ...record, state: 'revoked' });
    return Ok(undefined);
  }
}

/** Configurable outcomes for {@link ScriptedStore}. */
export interface ScriptedStoreOptions {
  readonly create?: Result<void, Problem>;
  readonly claim?: Result<DeferredNonceRecord, Problem>;
  readonly consume?: Result<void, Problem>;
  readonly revoke?: Result<void, Problem>;
}

/** A call-recording store whose every method returns a scripted result. */
export class ScriptedStore implements DeferredTokenStore {
  readonly calls = { create: 0, claim: 0, consume: 0, revoke: 0 };
  lastCreate: { nonce: string; record: DeferredNonceRecord } | undefined;
  readonly #options: ScriptedStoreOptions;

  constructor(options: ScriptedStoreOptions = {}) {
    this.#options = options;
  }

  create(nonce: string, record: DeferredNonceRecord): Result<void, Problem> {
    this.calls.create += 1;
    this.lastCreate = { nonce, record };
    return this.#options.create ?? Ok(undefined);
  }

  claim(_nonce: string): Result<DeferredNonceRecord, Problem> {
    this.calls.claim += 1;
    return this.#options.claim ?? Err(genericExpiry());
  }

  consume(_nonce: string): Result<void, Problem> {
    this.calls.consume += 1;
    return this.#options.consume ?? Ok(undefined);
  }

  revoke(_nonce: string): Result<void, Problem> {
    this.calls.revoke += 1;
    return this.#options.revoke ?? Ok(undefined);
  }
}

/** Configurable outcomes for {@link ScriptedIdentityClient}. */
export interface ScriptedIdentityOptions {
  readonly getUser?: Result<LogtoUserAccount, Problem>;
  readonly mint?: Result<OneTimeToken, Problem>;
}

/** A call-recording {@link DeferredIdentityClient} with scripted outcomes. */
export class ScriptedIdentityClient implements DeferredIdentityClient {
  readonly calls = { getUser: 0, mint: 0 };
  lastMintEmail: string | undefined;
  readonly #options: ScriptedIdentityOptions;

  constructor(options: ScriptedIdentityOptions = {}) {
    this.#options = options;
  }

  getUser(_sub: string): Result<LogtoUserAccount, Problem> {
    this.calls.getUser += 1;
    return this.#options.getUser ?? Err(genericExpiry());
  }

  mintOneTimeToken(email: string): Result<OneTimeToken, Problem> {
    this.calls.mint += 1;
    this.lastMintEmail = email;
    return this.#options.mint ?? Err(genericExpiry());
  }
}

/** Build a claimable record for scripted-store claim outcomes (expiry is inert here). */
export function claimedRecord(overrides: Partial<DeferredNonceRecord> = {}): DeferredNonceRecord {
  return {
    sub: 'usr_subject_1',
    email: 'user@example.com',
    expiresAt: Temporal.Instant.from('2026-07-24T12:15:00Z'),
    state: 'claimed',
    ...overrides,
  };
}
