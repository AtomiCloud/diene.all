/**
 * Scheduled-SIT-compatible exercise of the DORMANT rescue path (rot prevention,
 * per the goal's "scheduled SIT/e2e exercises the dormant path so it never
 * rots"). It drives the whole hard-connect-failure → Doc C → rescue-scan →
 * pin → persist → restart → heal lifecycle end-to-end against in-memory seams,
 * so it is fully deterministic and SSR-safe (no window/document/network).
 *
 * This file lives under tests/sit and is intended for the scheduled SIT tier.
 * It is deliberately NOT wired into the per-PR unit ledger (it asserts the
 * cross-module dormant path, not per-line domain coverage).
 */
import { describe, expect, test } from 'bun:test';
import type { Clock, Random, Storage, Transport, TransportOutcome, Wait } from '../../src/lib/discovery';
import {
  BROWSER_RESCUE_CONTEXT,
  candidatesFor,
  checkHeal,
  createVersionLedger,
  DEFAULT_ALLOWLIST,
  fetchDocC,
  NEXTJS_SERVER_RESCUE_CONTEXT,
  readLastKnownGood,
  retryOnceOnNetworkError,
  runRescue,
  tripOnConnectFailure,
} from '../../src/lib/discovery';

const CATALOG_HOST = 'https://catalog.lapras.cluster.atomi.cloud';
const PRIMARY = 'https://api.lapras.cluster.atomi.cloud';
const RESCUE_A = 'https://api.rescue-a.cluster.atomi.cloud';
const RESCUE_B = 'https://api.rescue-b.cluster.atomi.cloud';

const DOC_C = JSON.stringify({
  version: 1,
  platform: 'web',
  env: 'prod',
  lists: [{ landscape: 'lapras', service: 'api', module: 'core', candidates: [PRIMARY, RESCUE_A, RESCUE_B] }],
});

const CONNECT: TransportOutcome = { kind: 'connect-failure' };
const okOutcome = (body: string): TransportOutcome => ({ kind: 'ok', status: 200, body });

/** A programmable transport: per-URL response queues, connect-failure fallback. */
const transportOf = (map: Record<string, TransportOutcome[]>): Transport => ({
  fetch(url) {
    const next = map[url]?.shift();
    return Promise.resolve(next ?? CONNECT);
  },
});

const clockOf = (): Clock => {
  let value = 0;
  return {
    now() {
      const current = value;
      value += 1;
      return current;
    },
  };
};

const randomOf = (): Random => ({ next: () => 0.25 });
const waitOf = (): Wait => () => Promise.resolve();

const storageOf = (init: Record<string, string> = {}): Storage => {
  const map = new Map<string, string>(Object.entries(init));
  return {
    read: key => map.get(key) ?? null,
    write: (key, value) => {
      map.set(key, value);
    },
  };
};

const BUDGET = { maxAttempts: 4, budgetMs: 30_000, baseJitterMs: 100 };
const STORAGE_KEY = 'discovery:lkg:lapras/api/core';

describe('[SIT] dormant rescue path end-to-end', () => {
  test('trips only on a hard connect-failure, walks Doc C, pins + persists a rescue endpoint', async () => {
    // Arrange — the home hostname hard-fails on the hot path (retry-once first).
    const homeTransport = transportOf({ [PRIMARY]: [CONNECT, CONNECT] });
    const homeOutcome = await retryOnceOnNetworkError(homeTransport, PRIMARY);

    // Act — a soft/retryable error must NOT mint a trip token...
    expect(await tripOnConnectFailure({ kind: 'timeout' }).isErr()).toBe(true);
    // ...but this hard connect-failure does.
    const token = await tripOnConnectFailure(homeOutcome).unwrap();

    // Fetch the dormant Doc C (only possible with the token), from an edge host.
    const ledger = createVersionLedger();
    const docTransport = transportOf({ [CATALOG_HOST]: [okOutcome(DOC_C)] });
    const docCResult = await fetchDocC({
      host: CATALOG_HOST,
      transport: docTransport,
      allowlist: DEFAULT_ALLOWLIST,
      token,
      acceptVersion: ledger.accept,
    });
    const docC = await docCResult.unwrap();
    const candidates = candidatesFor(docC, { landscape: 'lapras', service: 'api', module: 'core' });
    expect(candidates).toEqual([PRIMARY, RESCUE_A, RESCUE_B]);

    // Rescue scan — primary still down, first rescue alternate is healthy.
    const storage = storageOf();
    const rescueTransport = transportOf({
      [PRIMARY]: [CONNECT, CONNECT],
      [RESCUE_A]: [okOutcome('')],
    });
    const rescueResult = await runRescue({
      context: BROWSER_RESCUE_CONTEXT,
      candidates,
      allowlist: DEFAULT_ALLOWLIST,
      transport: rescueTransport,
      clock: clockOf(),
      random: randomOf(),
      wait: waitOf(),
      budget: BUDGET,
      storage,
      storageKey: STORAGE_KEY,
    });
    const outcome = await rescueResult.unwrap();

    // Assert — pinned the first healthy candidate in Doc C order; persisted LKG.
    expect(outcome.pinnedUrl).toBe(RESCUE_A);
    expect(outcome.triedFromLastKnownGood).toBe(false);
    expect(readLastKnownGood(storage, STORAGE_KEY)).toBe(RESCUE_A);
  });

  test('retains last-known-good across a restart and re-pins it first', async () => {
    // Arrange — a fresh storage view seeded from disk (survives restart).
    const storage = storageOf({ [STORAGE_KEY]: RESCUE_A });
    const rescueTransport = transportOf({ [RESCUE_A]: [okOutcome('')] });

    // Act
    const rescueResult = await runRescue({
      context: BROWSER_RESCUE_CONTEXT,
      candidates: [PRIMARY, RESCUE_A, RESCUE_B],
      allowlist: DEFAULT_ALLOWLIST,
      transport: rescueTransport,
      clock: clockOf(),
      random: randomOf(),
      wait: waitOf(),
      budget: BUDGET,
      storage,
      storageKey: STORAGE_KEY,
    });
    const outcome = await rescueResult.unwrap();

    // Assert — the retained LKG was tried first and re-pinned.
    expect(outcome.pinnedUrl).toBe(RESCUE_A);
    expect(outcome.triedFromLastKnownGood).toBe(true);
  });

  test('detects the primary healing so the hot path can drop the pin', async () => {
    const healed = transportOf({ [PRIMARY]: [okOutcome('')] });
    expect(await checkHeal(healed, PRIMARY)).toBe(true);

    const stillDown = transportOf({ [PRIMARY]: [CONNECT, CONNECT] });
    expect(await checkHeal(stillDown, PRIMARY)).toBe(false);
  });

  test('is disabled by construction in the nextjs server runtime', async () => {
    const result = await runRescue({
      context: NEXTJS_SERVER_RESCUE_CONTEXT,
      candidates: [PRIMARY, RESCUE_A],
      allowlist: DEFAULT_ALLOWLIST,
      transport: transportOf({ [RESCUE_A]: [okOutcome('')] }),
      clock: clockOf(),
      random: randomOf(),
      wait: waitOf(),
      budget: BUDGET,
      storage: storageOf(),
      storageKey: STORAGE_KEY,
    });

    expect((await result.unwrapErr()).kind).toBe('rescue-disabled');
  });
});
