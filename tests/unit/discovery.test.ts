import { describe, expect, test } from 'bun:test';
import type {
  AllowlistConfig,
  Clock,
  DocB,
  Random,
  RescueTripToken,
  Storage,
  Transport,
  TransportOutcome,
  Wait,
} from '../../src/lib/discovery';
import {
  BROWSER_RESCUE_CONTEXT,
  candidatesFor,
  checkHeal,
  createRescueContext,
  createVersionLedger,
  DEFAULT_ALLOWLIST,
  DOC_A_LEDGER_KEY,
  DOC_C_LEDGER_KEY,
  derivePingUrl,
  FLUTTER_RESCUE_CONTEXT,
  fetchDocC,
  fetchProblemCatalog,
  handoffToAuthEngine,
  isHardConnectFailure,
  isHostAllowed,
  NEXTJS_SERVER_RESCUE_CONTEXT,
  parseDocA,
  parseDocB,
  parseDocC,
  pickHome,
  pingLandscapes,
  readLastKnownGood,
  refreshDocA,
  retryOnceOnNetworkError,
  runRescue,
  tripOnConnectFailure,
  validateEndpoint,
} from '../../src/lib/discovery';

// ─── Seams / fakes ──────────────────────────────────────────────────────────

const ok = (body: string, status = 200): TransportOutcome => ({ kind: 'ok', status, body });
const CONNECT: TransportOutcome = { kind: 'connect-failure' };
const TIMEOUT: TransportOutcome = { kind: 'timeout' };
const httpErr = (status: number): TransportOutcome => ({ kind: 'http-error', status });

interface RecordingTransport extends Transport {
  readonly calls: string[];
}

const queueTransport = (
  map: Record<string, TransportOutcome[]>,
  fallback: TransportOutcome = CONNECT,
): RecordingTransport => {
  const calls: string[] = [];
  return {
    calls,
    fetch(url) {
      calls.push(url);
      const queue = map[url];
      const next = queue?.shift();
      return Promise.resolve(next ?? fallback);
    },
  };
};

const countingClock = (step = 1, start = 0): Clock => {
  let value = start;
  return {
    now() {
      const current = value;
      value += step;
      return current;
    },
  };
};

const scriptedClock = (values: readonly number[]): Clock => {
  let index = 0;
  return {
    now() {
      const value = values[index] ?? values[values.length - 1] ?? 0;
      index += 1;
      return value;
    },
  };
};

const seededRandom = (values: readonly number[]): Random => {
  let index = 0;
  return {
    next() {
      const value = values[index % values.length] ?? 0;
      index += 1;
      return value;
    },
  };
};

interface RecordingWait extends Wait {
  readonly waited: number[];
}

const recordingWait = (): RecordingWait => {
  const waited: number[] = [];
  const wait = ((ms: number) => {
    waited.push(ms);
    return Promise.resolve();
  }) as RecordingWait;
  Object.defineProperty(wait, 'waited', { value: waited });
  return wait;
};

const memoryStorage = (init: Record<string, string> = {}): Storage => {
  const map = new Map<string, string>(Object.entries(init));
  return {
    read(key) {
      return map.get(key) ?? null;
    },
    write(key, value) {
      map.set(key, value);
    },
  };
};

const TRIP: RescueTripToken = Object.freeze({ reason: 'hard-connect-failure' });

const VALID = 'https://api.lapras.cluster.atomi.cloud';
const RESCUE_ROOT = 'https://rescue.atomi.cloud';

// ─── allowlist ──────────────────────────────────────────────────────────────

describe('endpoint-suffix allowlist', () => {
  test('accepts a suffix host and an exact rescue root, rejects others', () => {
    // Arrange / Act / Assert
    expect(isHostAllowed('api.lapras.cluster.atomi.cloud', DEFAULT_ALLOWLIST)).toBe(true);
    expect(isHostAllowed('rescue.atomi.cloud', DEFAULT_ALLOWLIST)).toBe(true);
    expect(isHostAllowed('evil.example.com', DEFAULT_ALLOWLIST)).toBe(false);
  });

  test('validates https + host and returns the parsed URL', async () => {
    const result = validateEndpoint(VALID, DEFAULT_ALLOWLIST);
    expect(await result.isOk()).toBe(true);
    expect((await result.unwrap()).hostname).toBe('api.lapras.cluster.atomi.cloud');
    expect(await validateEndpoint(RESCUE_ROOT, DEFAULT_ALLOWLIST).isOk()).toBe(true);
  });

  test('rejects unparseable, non-https, and unauthorized hosts', async () => {
    const unparseable = validateEndpoint('http://', DEFAULT_ALLOWLIST);
    expect((await unparseable.unwrapErr()).kind).toBe('endpoint-unparseable');

    const notHttps = validateEndpoint('http://api.lapras.cluster.atomi.cloud', DEFAULT_ALLOWLIST);
    expect((await notHttps.unwrapErr()).kind).toBe('endpoint-not-https');

    const rejected = validateEndpoint('https://evil.example.com/x', DEFAULT_ALLOWLIST);
    const error = await rejected.unwrapErr();
    expect(error.kind).toBe('endpoint-suffix-rejected');
  });
});

// ─── version ledger ─────────────────────────────────────────────────────────

describe('per-document monotonic version ledger', () => {
  test('accepts first, equal, and newer; rejects older; tracks per key', async () => {
    const ledger = createVersionLedger();
    expect(ledger.seen('doc')).toBeUndefined();

    expect(await ledger.accept('doc', 5).unwrap()).toBe(5);
    expect(ledger.seen('doc')).toBe(5);
    expect(await ledger.accept('doc', 5).unwrap()).toBe(5); // equal (304-style refresh)
    expect(await ledger.accept('doc', 7).unwrap()).toBe(7); // newer

    const stale = ledger.accept('doc', 6);
    const error = await stale.unwrapErr();
    expect(error.kind).toBe('stale-version');

    // A different key is independent (not global).
    expect(await ledger.accept('other', 1).unwrap()).toBe(1);
  });
});

// ─── parsing ────────────────────────────────────────────────────────────────

describe('Doc A parsing', () => {
  const base = { version: 1, ttlSeconds: 30, catalogHosts: [VALID] };

  test('parses a well-formed Doc A', async () => {
    const result = parseDocA(base);
    const doc = await result.unwrap();
    expect(doc.version).toBe(1);
    expect(doc.catalogHosts).toEqual([VALID]);
  });

  test.each([
    ['non-object root', 'nope'],
    ['bad version', { ...base, version: Number.NaN }],
    ['bad ttl', { ...base, ttlSeconds: 'x' }],
    ['bad catalogHosts', { ...base, catalogHosts: [1] }],
    ['empty catalogHosts', { ...base, catalogHosts: [] }],
  ])('rejects %s', async (_label, raw) => {
    const result = parseDocA(raw);
    expect((await result.unwrapErr()).kind).toBe('malformed-doc');
  });
});

describe('Doc B parsing', () => {
  const landscape = { name: 'lapras', displayName: 'Lapras', metadata: { region: 'ap' } };
  const base = { version: 2, platform: 'web', env: 'prod', landscapes: [landscape] };

  test('parses a well-formed Doc B', async () => {
    const doc = await parseDocB(base).unwrap();
    expect(doc.landscapes[0]?.name).toBe('lapras');
    expect(doc.landscapes[0]?.metadata.region).toBe('ap');
  });

  test.each([
    ['non-object root', 3],
    ['bad version', { ...base, version: 'x' }],
    ['bad platform', { ...base, platform: 1 }],
    ['bad env', { ...base, env: 1 }],
    ['landscapes not array', { ...base, landscapes: 'x' }],
    ['empty landscapes', { ...base, landscapes: [] }],
    ['landscape not object', { ...base, landscapes: ['x'] }],
    ['landscape bad name', { ...base, landscapes: [{ ...landscape, name: '' }] }],
    ['landscape bad displayName', { ...base, landscapes: [{ ...landscape, displayName: 1 }] }],
    ['landscape bad metadata', { ...base, landscapes: [{ ...landscape, metadata: { r: 1 } }] }],
    ['landscape metadata not record', { ...base, landscapes: [{ ...landscape, metadata: 5 }] }],
  ])('rejects %s', async (_label, raw) => {
    expect((await parseDocB(raw).unwrapErr()).kind).toBe('malformed-doc');
  });
});

describe('Doc C parsing', () => {
  const list = { landscape: 'lapras', service: 'auth', module: 'oidc', candidates: [VALID] };
  const base = { version: 3, platform: 'web', env: 'prod', lists: [list] };

  test('parses a well-formed Doc C', async () => {
    const doc = await parseDocC(base).unwrap();
    expect(doc.lists[0]?.candidates).toEqual([VALID]);
  });

  test.each([
    ['non-object root', 1],
    ['bad version', { ...base, version: 'x' }],
    ['bad platform', { ...base, platform: 1 }],
    ['bad env', { ...base, env: 1 }],
    ['lists not array', { ...base, lists: 'x' }],
    ['empty lists', { ...base, lists: [] }],
    ['list not object', { ...base, lists: ['x'] }],
    ['list bad landscape', { ...base, lists: [{ ...list, landscape: '' }] }],
    ['list bad service', { ...base, lists: [{ ...list, service: '' }] }],
    ['list bad module', { ...base, lists: [{ ...list, module: '' }] }],
    ['list empty candidates', { ...base, lists: [{ ...list, candidates: [] }] }],
    ['list bad candidates', { ...base, lists: [{ ...list, candidates: [1] }] }],
  ])('rejects %s', async (_label, raw) => {
    expect((await parseDocC(raw).unwrapErr()).kind).toBe('malformed-doc');
  });
});

// ─── transport (hot path) ───────────────────────────────────────────────────

describe('hot-path transport primitives', () => {
  test('returns immediately on a non-network outcome', async () => {
    const transport = queueTransport({ [VALID]: [ok('{}')] });
    const outcome = await retryOnceOnNetworkError(transport, VALID);
    expect(outcome.kind).toBe('ok');
    expect(transport.calls).toHaveLength(1);
  });

  test('does not retry an http error response', async () => {
    const transport = queueTransport({ [VALID]: [httpErr(503)] });
    const outcome = await retryOnceOnNetworkError(transport, VALID);
    expect(outcome.kind).toBe('http-error');
    expect(transport.calls).toHaveLength(1);
  });

  test('retries exactly once on a network error', async () => {
    const transport = queueTransport({ [VALID]: [TIMEOUT, ok('{}')] });
    const outcome = await retryOnceOnNetworkError(transport, VALID);
    expect(outcome.kind).toBe('ok');
    expect(transport.calls).toHaveLength(2);
  });

  test('retries a hard connect-failure once, then surfaces it', async () => {
    const transport = queueTransport({ [VALID]: [CONNECT, CONNECT] });
    const outcome = await retryOnceOnNetworkError(transport, VALID);
    expect(outcome.kind).toBe('connect-failure');
    expect(transport.calls).toHaveLength(2);
  });

  test('classifies hard connect-failure only', () => {
    expect(isHardConnectFailure(CONNECT)).toBe(true);
    expect(isHardConnectFailure(TIMEOUT)).toBe(false);
    expect(isHardConnectFailure(ok('{}'))).toBe(false);
  });

  test('mints a trip token only on a hard connect-failure', async () => {
    expect((await tripOnConnectFailure(CONNECT).unwrap()).reason).toBe('hard-connect-failure');
    expect((await tripOnConnectFailure(TIMEOUT).unwrapErr()).kind).toBe('not-a-connect-failure');
    expect((await tripOnConnectFailure(httpErr(500)).unwrapErr()).kind).toBe('not-a-connect-failure');
  });
});

// ─── Doc A refresh (stale-while-revalidate) ─────────────────────────────────

describe('Doc A refresh from baked seeds', () => {
  const docJson = (version: number): string => JSON.stringify({ version, ttlSeconds: 30, catalogHosts: [VALID] });
  const seedA = 'https://seed-a.example.net/doc';
  const seedB = 'https://seed-b.example.net/doc';

  test('serves the first reachable, well-formed, newer seed', async () => {
    const ledger = createVersionLedger();
    const transport = queueTransport({ [seedA]: [ok(docJson(4))] });
    const result = await refreshDocA({ seeds: [seedA], transport, acceptVersion: ledger.accept, cached: null });
    const value = await result.unwrap();
    expect(value.source).toBe('network');
    expect(value.doc.version).toBe(4);
    expect(ledger.seen(DOC_A_LEDGER_KEY)).toBe(4);
  });

  test('skips unreachable, non-JSON, and malformed seeds then serves a later seed', async () => {
    const ledger = createVersionLedger();
    const transport = queueTransport({
      [seedA]: [CONNECT, CONNECT],
      [seedB]: [ok('not json')],
      'https://seed-c.example.net/doc': [ok(JSON.stringify({ version: 1 }))],
      'https://seed-d.example.net/doc': [ok(docJson(9))],
    });
    const result = await refreshDocA({
      seeds: [seedA, seedB, 'https://seed-c.example.net/doc', 'https://seed-d.example.net/doc'],
      transport,
      acceptVersion: ledger.accept,
      cached: null,
    });
    const value = await result.unwrap();
    expect(value.doc.version).toBe(9);
  });

  test('serves the retained cache when revalidation finds nothing newer', async () => {
    const ledger = createVersionLedger();
    await ledger.accept(DOC_A_LEDGER_KEY, 10).unwrap();
    const cached = await parseDocA({ version: 10, ttlSeconds: 30, catalogHosts: [VALID] }).unwrap();
    const transport = queueTransport({ [seedA]: [ok(docJson(8))] }); // older
    const result = await refreshDocA({ seeds: [seedA], transport, acceptVersion: ledger.accept, cached });
    const value = await result.unwrap();
    expect(value.source).toBe('cache');
    expect(value.doc.version).toBe(10);
  });

  test('returns the stale-version error when a stale seed arrives with no cache', async () => {
    const ledger = createVersionLedger();
    await ledger.accept(DOC_A_LEDGER_KEY, 10).unwrap();
    const transport = queueTransport({ [seedA]: [ok(docJson(8))] });
    const result = await refreshDocA({ seeds: [seedA], transport, acceptVersion: ledger.accept, cached: null });
    expect((await result.unwrapErr()).kind).toBe('stale-version');
  });

  test('serves stale cache when every seed is unreachable', async () => {
    const ledger = createVersionLedger();
    const cached = await parseDocA({ version: 2, ttlSeconds: 30, catalogHosts: [VALID] }).unwrap();
    const transport = queueTransport({}, CONNECT);
    const result = await refreshDocA({ seeds: [seedA], transport, acceptVersion: ledger.accept, cached });
    const value = await result.unwrap();
    expect(value.source).toBe('cache');
  });

  test('errors when every seed fails and there is no cache', async () => {
    const ledger = createVersionLedger();
    const transport = queueTransport({}, CONNECT);
    const result = await refreshDocA({ seeds: [seedA], transport, acceptVersion: ledger.accept, cached: null });
    expect((await result.unwrapErr()).kind).toBe('catalog-fetch-failed');
  });

  test('errors with the sentinel when no seeds are configured and there is no cache', async () => {
    const ledger = createVersionLedger();
    const transport = queueTransport({});
    const result = await refreshDocA({ seeds: [], transport, acceptVersion: ledger.accept, cached: null });
    expect((await result.unwrapErr()).kind).toBe('malformed-doc');
  });
});

// ─── Problem-catalog fetch ──────────────────────────────────────────────────

describe('Problem-catalog fetch from edge hosts', () => {
  const resource = {
    apiVersion: 'atomi.cloud/v1alpha1',
    kind: 'Problem',
    metadata: { name: 'auth', namespace: 'svc' },
    spec: {
      platform: 'web',
      service: 'auth',
      landscape: 'lapras',
      version: '1',
      problems: [{ id: 'e1', type: 't', title: 'T', status: 400, recoverable: true, schema: {}, endpoints: [] }],
    },
  };

  test('fetches and validates a Problem resource', async () => {
    const transport = queueTransport({ [VALID]: [ok(JSON.stringify(resource))] });
    const result = await fetchProblemCatalog(VALID, transport, DEFAULT_ALLOWLIST);
    const value = await result.unwrap();
    expect(value.spec.service).toBe('auth');
  });

  test('rejects a host outside the allowlist before fetching', async () => {
    const transport = queueTransport({});
    const result = await fetchProblemCatalog('https://evil.example.com', transport, DEFAULT_ALLOWLIST);
    expect((await result.unwrapErr()).kind).toBe('endpoint-suffix-rejected');
    expect(transport.calls).toHaveLength(0);
  });

  test('fails on unreachable host', async () => {
    const transport = queueTransport({ [VALID]: [CONNECT, CONNECT] });
    const result = await fetchProblemCatalog(VALID, transport, DEFAULT_ALLOWLIST);
    expect((await result.unwrapErr()).kind).toBe('catalog-fetch-failed');
  });

  test('fails on non-JSON body', async () => {
    const transport = queueTransport({ [VALID]: [ok('not json')] });
    const result = await fetchProblemCatalog(VALID, transport, DEFAULT_ALLOWLIST);
    expect((await result.unwrapErr()).kind).toBe('catalog-fetch-failed');
  });

  test.each([
    ['not a record', 'hello'],
    ['wrong apiVersion', { ...resource, apiVersion: 'x' }],
    ['wrong kind', { ...resource, kind: 'x' }],
    ['bad metadata', { ...resource, metadata: { name: 'a' } }],
    ['spec not a record', { ...resource, spec: 5 }],
    ['bad spec scalar', { ...resource, spec: { ...resource.spec, platform: 1 } }],
    ['problems not array', { ...resource, spec: { ...resource.spec, problems: 5 } }],
    ['problem entry invalid', { ...resource, spec: { ...resource.spec, problems: [{ id: 'e' }] } }],
  ])('rejects a body that is %s', async (_label, body) => {
    const transport = queueTransport({ [VALID]: [ok(JSON.stringify(body))] });
    const result = await fetchProblemCatalog(VALID, transport, DEFAULT_ALLOWLIST);
    expect((await result.unwrapErr()).kind).toBe('catalog-fetch-failed');
  });
});

// ─── Doc B ping-and-pick-home ───────────────────────────────────────────────

const docB = (names: readonly string[]): DocB =>
  Object.freeze({
    version: 1,
    platform: 'web',
    env: 'prod',
    landscapes: names.map(name => ({ name, displayName: name, metadata: {} })),
  });

describe('Doc B ping-and-pick-home', () => {
  test('derives ping URLs by convention', () => {
    expect(derivePingUrl('lapras', { root: 'cluster.atomi.cloud' })).toBe('https://ping.lapras.cluster.atomi.cloud');
  });

  test('pings valid landscapes, skips allowlist-rejected ones, orders reachable-first then latency', async () => {
    const doc = docB(['lapras', 'a/b', 'pikachu', 'raichu']);
    const transport = queueTransport({
      'https://ping.lapras.cluster.atomi.cloud': [ok('')],
      'https://ping.pikachu.cluster.atomi.cloud': [CONNECT, CONNECT],
      'https://ping.raichu.cluster.atomi.cloud': [ok('')],
    });
    // lapras: 10..15 (5), raichu: 20..22 (2); pikachu unreachable 30..38 (8)
    const clock = scriptedClock([10, 15, 30, 38, 20, 22]);
    const pings = await pingLandscapes(doc, { root: 'cluster.atomi.cloud' }, transport, clock, DEFAULT_ALLOWLIST);

    expect(pings.map(p => p.landscape)).toEqual(['raichu', 'lapras', 'pikachu']);
    expect(pings.find(p => p.landscape === 'raichu')?.latencyMs).toBe(2);
    expect(pings.find(p => p.landscape === 'pikachu')?.reachable).toBe(false);
  });

  test('breaks latency ties by landscape name', async () => {
    const doc = docB(['charlie', 'alpha', 'bravo']);
    const transport = queueTransport({
      'https://ping.charlie.cluster.atomi.cloud': [ok('')],
      'https://ping.alpha.cluster.atomi.cloud': [ok('')],
      'https://ping.bravo.cluster.atomi.cloud': [ok('')],
    });
    const clock = scriptedClock([0, 3, 0, 3, 0, 3]); // all latency 3
    const pings = await pingLandscapes(doc, { root: 'cluster.atomi.cloud' }, transport, clock, DEFAULT_ALLOWLIST);
    expect(pings.map(p => p.landscape)).toEqual(['alpha', 'bravo', 'charlie']);
  });

  test('treats equal-named, equal-latency entries as equal', async () => {
    const doc = docB(['same', 'same']);
    const transport = queueTransport({ 'https://ping.same.cluster.atomi.cloud': [ok(''), ok('')] });
    const clock = scriptedClock([0, 1, 0, 1]);
    const pings = await pingLandscapes(doc, { root: 'cluster.atomi.cloud' }, transport, clock, DEFAULT_ALLOWLIST);
    expect(pings).toHaveLength(2);
  });

  test('picks a reachable home and hands it off to auth-engine', async () => {
    const pings = [
      { landscape: 'lapras', url: VALID, reachable: true, latencyMs: 5 },
      { landscape: 'pikachu', url: 'https://ping.pikachu.cluster.atomi.cloud', reachable: false, latencyMs: 9 },
    ];
    const assignment = await pickHome(pings, 'lapras').unwrap();
    expect(assignment.landscape).toBe('lapras');

    const handoff = handoffToAuthEngine(assignment);
    expect(handoff.kind).toBe('home-assignment');
    expect(handoff.pingUrl).toBe(VALID);
  });

  test('refuses to pick a missing or unreachable landscape', async () => {
    const pings = [
      { landscape: 'pikachu', url: 'https://ping.pikachu.cluster.atomi.cloud', reachable: false, latencyMs: 9 },
    ];
    expect((await pickHome(pings, 'lapras').unwrapErr()).kind).toBe('no-home-picked'); // missing
    expect((await pickHome(pings, 'pikachu').unwrapErr()).kind).toBe('no-home-picked'); // unreachable
  });
});

// ─── Doc C (dormant, token-gated) ───────────────────────────────────────────

describe('Doc C fetch is dormant and token-gated', () => {
  const docCJson = (version: number): string =>
    JSON.stringify({
      version,
      platform: 'web',
      env: 'prod',
      lists: [{ landscape: 'lapras', service: 'auth', module: 'oidc', candidates: [VALID, RESCUE_ROOT] }],
    });

  test('fetches and version-checks Doc C under a valid trip token', async () => {
    const ledger = createVersionLedger();
    const transport = queueTransport({ [VALID]: [ok(docCJson(1))] });
    const result = await fetchDocC({
      host: VALID,
      transport,
      allowlist: DEFAULT_ALLOWLIST,
      token: TRIP,
      acceptVersion: ledger.accept,
    });
    const doc = await result.unwrap();
    expect(candidatesFor(doc, { landscape: 'lapras', service: 'auth', module: 'oidc' })).toEqual([VALID, RESCUE_ROOT]);
    expect(ledger.seen(DOC_C_LEDGER_KEY)).toBe(1);
  });

  test('refuses a forged/invalid trip token', async () => {
    const ledger = createVersionLedger();
    const transport = queueTransport({ [VALID]: [ok(docCJson(1))] });
    const forged = { reason: 'nope' } as unknown as RescueTripToken;
    const result = await fetchDocC({
      host: VALID,
      transport,
      allowlist: DEFAULT_ALLOWLIST,
      token: forged,
      acceptVersion: ledger.accept,
    });
    expect((await result.unwrapErr()).kind).toBe('doc-c-fetch-forbidden');
    expect(transport.calls).toHaveLength(0);
  });

  test('rejects a doc-sourced host outside the allowlist', async () => {
    const ledger = createVersionLedger();
    const transport = queueTransport({});
    const result = await fetchDocC({
      host: 'https://evil.example.com',
      transport,
      allowlist: DEFAULT_ALLOWLIST,
      token: TRIP,
      acceptVersion: ledger.accept,
    });
    expect((await result.unwrapErr()).kind).toBe('endpoint-suffix-rejected');
  });

  test('fails on unreachable, non-JSON, malformed, and stale Doc C', async () => {
    const ledger = createVersionLedger();
    await ledger.accept(DOC_C_LEDGER_KEY, 5).unwrap();

    const unreachable = await fetchDocC({
      host: VALID,
      transport: queueTransport({ [VALID]: [CONNECT, CONNECT] }),
      allowlist: DEFAULT_ALLOWLIST,
      token: TRIP,
      acceptVersion: ledger.accept,
    });
    expect((await unreachable.unwrapErr()).kind).toBe('catalog-fetch-failed');

    const badJson = await fetchDocC({
      host: VALID,
      transport: queueTransport({ [VALID]: [ok('not json')] }),
      allowlist: DEFAULT_ALLOWLIST,
      token: TRIP,
      acceptVersion: ledger.accept,
    });
    expect((await badJson.unwrapErr()).kind).toBe('malformed-doc');

    const malformed = await fetchDocC({
      host: VALID,
      transport: queueTransport({ [VALID]: [ok('{"version":1}')] }),
      allowlist: DEFAULT_ALLOWLIST,
      token: TRIP,
      acceptVersion: ledger.accept,
    });
    expect((await malformed.unwrapErr()).kind).toBe('malformed-doc');

    const stale = await fetchDocC({
      host: VALID,
      transport: queueTransport({ [VALID]: [ok(docCJson(2))] }),
      allowlist: DEFAULT_ALLOWLIST,
      token: TRIP,
      acceptVersion: ledger.accept,
    });
    expect((await stale.unwrapErr()).kind).toBe('stale-version');
  });

  test('returns an empty candidate list for an unknown key', () => {
    const doc = {
      version: 1,
      platform: 'web',
      env: 'prod',
      lists: [{ landscape: 'lapras', service: 'auth', module: 'oidc', candidates: [VALID] }],
    } as const;
    expect(candidatesFor(doc, { landscape: 'nope', service: 'x', module: 'y' })).toEqual([]);
  });
});

// ─── Dormant rescue router ──────────────────────────────────────────────────

const allow = (extra: readonly string[] = []): AllowlistConfig => ({
  suffixes: [...DEFAULT_ALLOWLIST.suffixes],
  rescueRoots: [...DEFAULT_ALLOWLIST.rescueRoots, ...extra],
});

const budget = { maxAttempts: 5, budgetMs: 10_000, baseJitterMs: 50 };

describe('dormant rescue router', () => {
  test('exposes canonical per-context enable flags', () => {
    expect(BROWSER_RESCUE_CONTEXT.enabled).toBe(true);
    expect(FLUTTER_RESCUE_CONTEXT.enabled).toBe(true);
    expect(NEXTJS_SERVER_RESCUE_CONTEXT.enabled).toBe(false);
    expect(createRescueContext('x', true).enabled).toBe(true);
  });

  test('is a no-op when the context has rescue disabled (nextjs server)', async () => {
    const result = await runRescue({
      context: NEXTJS_SERVER_RESCUE_CONTEXT,
      candidates: [VALID],
      allowlist: DEFAULT_ALLOWLIST,
      transport: queueTransport({ [VALID]: [ok('')] }),
      clock: countingClock(),
      random: seededRandom([0]),
      wait: recordingWait(),
      budget,
      storage: memoryStorage(),
      storageKey: 'lkg',
    });
    expect((await result.unwrapErr()).kind).toBe('rescue-disabled');
  });

  test('walks candidates in order with jitter, pins + persists the first reachable', async () => {
    const wait = recordingWait();
    const storage = memoryStorage();
    const random = seededRandom([0.5, 1]);
    const result = await runRescue({
      context: BROWSER_RESCUE_CONTEXT,
      candidates: [VALID, RESCUE_ROOT],
      allowlist: DEFAULT_ALLOWLIST,
      transport: queueTransport({ [VALID]: [CONNECT, CONNECT], [RESCUE_ROOT]: [ok('')] }),
      clock: countingClock(),
      random,
      wait,
      budget,
      storage,
      storageKey: 'lkg',
    });
    const outcome = await result.unwrap();
    expect(outcome.pinnedUrl).toBe(RESCUE_ROOT);
    expect(outcome.attempts).toBe(2);
    expect(outcome.triedFromLastKnownGood).toBe(false);
    expect(wait.waited).toEqual([25, 50]); // floor(50*0.5), floor(50*1)
    expect(readLastKnownGood(storage, 'lkg')).toBe(RESCUE_ROOT);
  });

  test('skips allowlist-rejected candidates without spending an attempt', async () => {
    const result = await runRescue({
      context: BROWSER_RESCUE_CONTEXT,
      candidates: ['https://evil.example.com', VALID],
      allowlist: DEFAULT_ALLOWLIST,
      transport: queueTransport({ [VALID]: [ok('')] }),
      clock: countingClock(),
      random: seededRandom([0]),
      wait: recordingWait(),
      budget,
      storage: memoryStorage(),
      storageKey: 'lkg',
    });
    const outcome = await result.unwrap();
    expect(outcome.pinnedUrl).toBe(VALID);
    expect(outcome.attempts).toBe(1);
  });

  test('tries the last-known-good first on a subsequent trip', async () => {
    const storage = memoryStorage({ lkg: RESCUE_ROOT });
    const transport = queueTransport({ [RESCUE_ROOT]: [ok('')] });
    const result = await runRescue({
      context: BROWSER_RESCUE_CONTEXT,
      candidates: [VALID, RESCUE_ROOT],
      allowlist: DEFAULT_ALLOWLIST,
      transport,
      clock: countingClock(),
      random: seededRandom([0]),
      wait: recordingWait(),
      budget,
      storage,
      storageKey: 'lkg',
    });
    const outcome = await result.unwrap();
    expect(outcome.pinnedUrl).toBe(RESCUE_ROOT);
    expect(outcome.triedFromLastKnownGood).toBe(true);
    expect(transport.calls[0]).toBe(RESCUE_ROOT); // LKG attempted first
  });

  test('ignores a last-known-good that is not among the current candidates', async () => {
    const storage = memoryStorage({ lkg: 'https://old.cluster.atomi.cloud' });
    const transport = queueTransport({ [VALID]: [ok('')] });
    const result = await runRescue({
      context: BROWSER_RESCUE_CONTEXT,
      candidates: [VALID],
      allowlist: DEFAULT_ALLOWLIST,
      transport,
      clock: countingClock(),
      random: seededRandom([0]),
      wait: recordingWait(),
      budget,
      storage,
      storageKey: 'lkg',
    });
    const outcome = await result.unwrap();
    expect(outcome.triedFromLastKnownGood).toBe(false);
    expect(transport.calls[0]).toBe(VALID);
  });

  test('ignores an unparseable last-known-good', async () => {
    const storage = memoryStorage({ lkg: 'not a url' });
    const transport = queueTransport({ [VALID]: [ok('')] });
    const result = await runRescue({
      context: BROWSER_RESCUE_CONTEXT,
      candidates: ['not a url', VALID],
      allowlist: DEFAULT_ALLOWLIST,
      transport,
      clock: countingClock(),
      random: seededRandom([0]),
      wait: recordingWait(),
      budget,
      storage,
      storageKey: 'lkg',
    });
    const outcome = await result.unwrap();
    expect(outcome.triedFromLastKnownGood).toBe(false);
    expect(outcome.pinnedUrl).toBe(VALID);
  });

  test('ignores a last-known-good whose host is no longer allowed', async () => {
    const wide = allow(['legacy.example.com']);
    const storage = memoryStorage({ lkg: 'https://legacy.example.com' });
    // Rescue runs under the strict default allowlist even though the LKG was
    // stored under a wider one: the disallowed LKG must be dropped.
    const transport = queueTransport({ [VALID]: [ok('')] });
    const result = await runRescue({
      context: BROWSER_RESCUE_CONTEXT,
      candidates: ['https://legacy.example.com', VALID],
      allowlist: DEFAULT_ALLOWLIST,
      transport,
      clock: countingClock(),
      random: seededRandom([0]),
      wait: recordingWait(),
      budget,
      storage,
      storageKey: 'lkg',
    });
    // sanity: the wide allowlist would have accepted the legacy host
    expect(isHostAllowed('legacy.example.com', wide)).toBe(true);
    const outcome = await result.unwrap();
    expect(outcome.triedFromLastKnownGood).toBe(false);
    expect(outcome.pinnedUrl).toBe(VALID);
  });

  test('stops on the attempt budget', async () => {
    const result = await runRescue({
      context: BROWSER_RESCUE_CONTEXT,
      candidates: [VALID, RESCUE_ROOT],
      allowlist: DEFAULT_ALLOWLIST,
      transport: queueTransport({}, CONNECT),
      clock: countingClock(),
      random: seededRandom([0]),
      wait: recordingWait(),
      budget: { maxAttempts: 0, budgetMs: 10_000, baseJitterMs: 50 },
      storage: memoryStorage(),
      storageKey: 'lkg',
    });
    const error = await result.unwrapErr();
    expect(error.kind).toBe('rescue-budget-exhausted');
  });

  test('stops on the wall-clock budget', async () => {
    const result = await runRescue({
      context: BROWSER_RESCUE_CONTEXT,
      candidates: [VALID, RESCUE_ROOT],
      allowlist: DEFAULT_ALLOWLIST,
      transport: queueTransport({}, CONNECT),
      clock: countingClock(),
      random: seededRandom([0]),
      wait: recordingWait(),
      budget: { maxAttempts: 5, budgetMs: 0, baseJitterMs: 50 },
      storage: memoryStorage(),
      storageKey: 'lkg',
    });
    expect((await result.unwrapErr()).kind).toBe('rescue-budget-exhausted');
  });

  test('reports no candidate reachable when the whole ordered list fails within budget', async () => {
    const result = await runRescue({
      context: BROWSER_RESCUE_CONTEXT,
      candidates: [VALID, RESCUE_ROOT],
      allowlist: DEFAULT_ALLOWLIST,
      transport: queueTransport({}, CONNECT),
      clock: countingClock(),
      random: seededRandom([0]),
      wait: recordingWait(),
      budget,
      storage: memoryStorage(),
      storageKey: 'lkg',
    });
    const error = await result.unwrapErr();
    expect(error.kind).toBe('no-candidate-reachable');
  });

  test('checks whether the pinned primary has healed', async () => {
    expect(await checkHeal(queueTransport({ [VALID]: [ok('')] }), VALID)).toBe(true);
    expect(await checkHeal(queueTransport({}, CONNECT), VALID)).toBe(false);
  });
});
