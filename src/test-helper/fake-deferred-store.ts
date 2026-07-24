import type { Problem } from '@atomicloud/diene.problems';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import { z } from 'zod';
import { type Clock, type DeferredNonceRecord, type DeferredTokenStore, systemClock } from '../lib/deferred/store';
import { type AuthProblems, createAppHandoffExpired } from '../lib/problems';

export interface InMemoryDeferredStoreOptions {
  readonly clock?: Clock;
  readonly problems?: Pick<AuthProblems, 'AppHandoffExpired'>;
}

const nonceSchema = z.string().regex(/^[A-Za-z0-9_-]{43}$/);
const deferredNonceRecordSchema = z
  .object({
    sub: z.string().trim().min(1),
    email: z.string().trim().min(1),
    expiresAt: z.custom<Temporal.Instant>(value => value instanceof Temporal.Instant),
    state: z.enum(['active', 'claimed', 'consumed', 'revoked']),
  })
  .strict();

function fallbackExpired(): Problem {
  return {
    type: 'about:blank',
    title: 'App handoff expired',
    status: 410,
    detail: 'This app handoff is expired or invalid.',
    data: {},
  };
}

function expiredProblem(problems: Pick<AuthProblems, 'AppHandoffExpired'> | undefined): Problem {
  return problems === undefined ? fallbackExpired() : createAppHandoffExpired(problems);
}

function isLive(record: DeferredNonceRecord, clock: Clock): boolean {
  return Temporal.Instant.compare(clock.now(), record.expiresAt) < 0;
}

export class InMemoryDeferredStore implements DeferredTokenStore {
  readonly #records = new Map<string, DeferredNonceRecord>();
  readonly #clock: Clock;
  readonly #problems?: Pick<AuthProblems, 'AppHandoffExpired'>;
  storeHits = 0;

  constructor(options: InMemoryDeferredStoreOptions = {}) {
    this.#clock = options.clock ?? systemClock;
    this.#problems = options.problems;
  }

  create(nonce: string, record: DeferredNonceRecord): Result<void, Problem> {
    const parsedNonce = nonceSchema.safeParse(nonce);
    const parsedRecord = deferredNonceRecordSchema.safeParse(record);
    if (!parsedNonce.success || !parsedRecord.success) return Err(expiredProblem(this.#problems));
    this.storeHits += 1;
    const existing = this.#records.get(parsedNonce.data);
    if (existing !== undefined && !isLive(existing, this.#clock)) this.#records.delete(parsedNonce.data);
    if (this.#records.has(parsedNonce.data) || !isLive(parsedRecord.data, this.#clock)) {
      return Err(expiredProblem(this.#problems));
    }
    this.#records.set(parsedNonce.data, Object.freeze({ ...parsedRecord.data, state: 'active' }));
    return Ok(undefined);
  }

  claim(nonce: string): Result<DeferredNonceRecord, Problem> {
    const parsed = nonceSchema.safeParse(nonce);
    if (!parsed.success) return Err(expiredProblem(this.#problems));
    this.storeHits += 1;
    const record = this.#records.get(parsed.data);
    if (record !== undefined && !isLive(record, this.#clock)) this.#records.delete(parsed.data);
    if (record === undefined || record.state !== 'active' || !isLive(record, this.#clock)) {
      return Err(expiredProblem(this.#problems));
    }
    const claimed = Object.freeze({ ...record, state: 'claimed' } as const);
    this.#records.set(parsed.data, claimed);
    return Ok(claimed);
  }

  consume(nonce: string): Result<void, Problem> {
    const parsed = nonceSchema.safeParse(nonce);
    if (!parsed.success) return Err(expiredProblem(this.#problems));
    this.storeHits += 1;
    const record = this.#records.get(parsed.data);
    if (record !== undefined && !isLive(record, this.#clock)) this.#records.delete(parsed.data);
    if (record === undefined || record.state !== 'claimed' || !isLive(record, this.#clock)) {
      return Err(expiredProblem(this.#problems));
    }
    this.#records.set(parsed.data, Object.freeze({ ...record, state: 'consumed' }));
    return Ok(undefined);
  }

  revoke(nonce: string): Result<void, Problem> {
    const parsed = nonceSchema.safeParse(nonce);
    if (!parsed.success) return Err(expiredProblem(this.#problems));
    this.storeHits += 1;
    const record = this.#records.get(parsed.data);
    if (record !== undefined && !isLive(record, this.#clock)) this.#records.delete(parsed.data);
    if (record === undefined || !isLive(record, this.#clock)) return Err(expiredProblem(this.#problems));
    if (record.state !== 'revoked') {
      this.#records.set(parsed.data, Object.freeze({ ...record, state: 'revoked' }));
    }
    return Ok(undefined);
  }

  inspect(nonce: string): DeferredNonceRecord | undefined {
    return this.#records.get(nonce);
  }
}
