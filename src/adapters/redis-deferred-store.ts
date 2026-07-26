import type { Problem } from '@atomicloud/diene.problems';
import { Err, Ok, Res, type Result } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import { Redis } from 'ioredis';
import { z } from 'zod';
import type { DeferredNonceRecord, DeferredTokenStore, NonceState } from '../lib/deferred/store';
import { type AuthProblems, createAppHandoffExpired } from '../lib/problems';

/** Redis connection coordinates (mirrors the engine config `store` block). */
export interface RedisConnection {
  readonly host: string;
  readonly port: number;
}

interface RedisDeferredStoreBase {
  readonly problems: Pick<AuthProblems, 'AppHandoffExpired'>;
  /** Key prefix for stored nonces; defaults to `diene:app-handoff:`. */
  readonly keyPrefix?: string;
}

/**
 * Dependencies for {@link RedisDeferredStore}. A discriminated union makes
 * invalid construction unrepresentable: exactly one of a pre-built `client`
 * (tests) or a `connection` (production) must be supplied — no runtime throw.
 */
export type RedisDeferredStoreDeps =
  | (RedisDeferredStoreBase & { readonly client: Redis; readonly connection?: undefined })
  | (RedisDeferredStoreBase & { readonly connection: RedisConnection; readonly client?: undefined });

const DEFAULT_KEY_PREFIX = 'diene:app-handoff:';

/**
 * Atomic `active → claimed` claim: reads the record, verifies it is `active`,
 * flips it to `claimed`, and preserves the existing PEXPIREAT TTL (`KEEPTTL`).
 * Returns the (now-claimed) record JSON, or `nil` for any missing/expired/
 * non-active state. Expired nonces are already gone via PEXPIREAT.
 */
const CLAIM_SCRIPT = `
local raw = redis.call('GET', KEYS[1])
if not raw then return nil end
local ok, rec = pcall(cjson.decode, raw)
if not ok then return nil end
if rec.state ~= 'active' then return nil end
rec.state = 'claimed'
redis.call('SET', KEYS[1], cjson.encode(rec), 'KEEPTTL')
return cjson.encode(rec)
`;

/** Transition `claimed → consumed`. Returns 1 on success, 0 otherwise. */
const CONSUME_SCRIPT = `
local raw = redis.call('GET', KEYS[1])
if not raw then return 0 end
local rec = cjson.decode(raw)
if rec.state ~= 'claimed' then return 0 end
rec.state = 'consumed'
redis.call('SET', KEYS[1], cjson.encode(rec), 'KEEPTTL')
return 1
`;

/** Transition any live record to `revoked` (idempotent). Returns 1 if present, 0 if absent. */
const REVOKE_SCRIPT = `
local raw = redis.call('GET', KEYS[1])
if not raw then return 0 end
local rec = cjson.decode(raw)
rec.state = 'revoked'
redis.call('SET', KEYS[1], cjson.encode(rec), 'KEEPTTL')
return 1
`;

const NONCE_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const domainRecordSchema = z
  .object({
    sub: z.string().trim().min(1),
    email: z.string().trim().min(1),
    expiresAt: z.custom<Temporal.Instant>(value => value instanceof Temporal.Instant),
    state: z.enum(['active', 'claimed', 'consumed', 'revoked'] satisfies readonly NonceState[]),
  })
  .strict();
const storedRecordSchema = z
  .object({
    sub: z.string().trim().min(1),
    email: z.string().trim().min(1),
    expiresAt: z.string().min(1),
    state: z.enum(['active', 'claimed', 'consumed', 'revoked'] satisfies readonly NonceState[]),
  })
  .strict();

/** Deserialise a stored JSON record; the wire `expiresAt` string becomes an instant. */
function parseRecord(raw: string): DeferredNonceRecord | null {
  try {
    const decoded: unknown = JSON.parse(raw);
    const parsed = storedRecordSchema.safeParse(decoded);
    if (!parsed.success) return null;
    return {
      sub: parsed.data.sub,
      email: parsed.data.email,
      expiresAt: Temporal.Instant.from(parsed.data.expiresAt),
      state: parsed.data.state,
    };
  } catch {
    return null;
  }
}

/** Serialise a record for storage; the domain instant becomes an RFC 3339 string. */
function serialiseRecord(record: DeferredNonceRecord): string {
  return JSON.stringify({
    sub: record.sub,
    email: record.email,
    expiresAt: record.expiresAt.toString(),
    state: record.state,
  });
}

function storageKey(prefix: string, nonce: string): string {
  return `${prefix}${nonce}`;
}

function isValidNonce(value: string): boolean {
  return NONCE_PATTERN.test(value);
}

function buildClient(connection: RedisConnection): Redis {
  return new Redis({
    host: connection.host,
    port: connection.port,
    maxRetriesPerRequest: 3,
    lazyConnect: true,
  });
}

/** Run a state-transition Lua script, returning whether exactly one row changed. */
async function runTransition(client: Redis, script: string, key: string): Promise<boolean> {
  try {
    return (await client.eval(script, 1, key)) === 1;
  } catch {
    return false;
  }
}

/**
 * Redis-backed {@link DeferredTokenStore} (int ledger). Claim/consume/revoke are
 * single-`EVAL` Lua scripts (read + state-check + write atomically); the TTL is
 * enforced by `PXAT` so expired nonces disappear. Every failure resolves to the
 * generic `AppHandoffExpired` problem (C0 §7 no-oracle rule). Only immutable
 * dependency fields are held.
 */
export class RedisDeferredStore implements DeferredTokenStore {
  readonly #client: Redis;
  readonly #problems: Pick<AuthProblems, 'AppHandoffExpired'>;
  readonly #prefix: string;

  constructor(deps: RedisDeferredStoreDeps) {
    this.#problems = deps.problems;
    this.#prefix = deps.keyPrefix ?? DEFAULT_KEY_PREFIX;
    this.#client = deps.client !== undefined ? deps.client : buildClient(deps.connection);
  }

  create(nonce: string, record: DeferredNonceRecord): Result<void, Problem> {
    return Res.async<void, Problem>(async () => {
      try {
        // M33: reject malformed nonce/record values before any Redis call.
        const parsedRecord = domainRecordSchema.safeParse(record);
        if (
          !isValidNonce(nonce) ||
          !parsedRecord.success ||
          Temporal.Instant.compare(Temporal.Now.instant(), parsedRecord.data.expiresAt) >= 0
        ) {
          return Err(createAppHandoffExpired(this.#problems));
        }
        const stored = serialiseRecord({ ...parsedRecord.data, state: 'active' });
        const outcome = await this.#client.set(
          storageKey(this.#prefix, nonce),
          stored,
          'PXAT',
          parsedRecord.data.expiresAt.epochMilliseconds,
          'NX',
        );
        return outcome === 'OK' ? Ok(undefined) : Err(createAppHandoffExpired(this.#problems));
      } catch {
        return Err(createAppHandoffExpired(this.#problems));
      }
    });
  }

  claim(nonce: string): Result<DeferredNonceRecord, Problem> {
    return Res.async<DeferredNonceRecord, Problem>(async () => {
      // M33: reject a blank nonce before any Redis call.
      if (!isValidNonce(nonce)) {
        return Err(createAppHandoffExpired(this.#problems));
      }
      try {
        const raw = (await this.#client.eval(CLAIM_SCRIPT, 1, storageKey(this.#prefix, nonce))) as string | null;
        const record = raw === null ? null : parseRecord(raw);
        return record === null ? Err(createAppHandoffExpired(this.#problems)) : Ok(record);
      } catch {
        return Err(createAppHandoffExpired(this.#problems));
      }
    });
  }

  consume(nonce: string): Result<void, Problem> {
    return Res.async<void, Problem>(async () => {
      // M33: reject a blank nonce before any Redis call.
      if (!isValidNonce(nonce)) {
        return Err(createAppHandoffExpired(this.#problems));
      }
      const changed = await runTransition(this.#client, CONSUME_SCRIPT, storageKey(this.#prefix, nonce));
      return changed ? Ok(undefined) : Err(createAppHandoffExpired(this.#problems));
    });
  }

  revoke(nonce: string): Result<void, Problem> {
    return Res.async<void, Problem>(async () => {
      // M33: reject a blank nonce before any Redis call.
      if (!isValidNonce(nonce)) {
        return Err(createAppHandoffExpired(this.#problems));
      }
      const changed = await runTransition(this.#client, REVOKE_SCRIPT, storageKey(this.#prefix, nonce));
      return changed ? Ok(undefined) : Err(createAppHandoffExpired(this.#problems));
    });
  }

  /** Guarded teardown (M32): a failed/closed `quit()` falls back to an idempotent `disconnect()`. */
  async close(): Promise<void> {
    try {
      await this.#client.quit();
    } catch {
      this.#client.disconnect();
    }
  }
}
