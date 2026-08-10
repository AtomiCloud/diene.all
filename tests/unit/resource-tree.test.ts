import { describe, it } from 'bun:test';
import { isProblem, type Problem } from '@atomicloud/diene.problems';
import { Err, Ok } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import should from 'should';
import { createSingleFlightCache } from '../../src/lib/cache';
import type { TokenResponse } from '../../src/lib/provider';
import {
  type BackendRegistration,
  type CanonicalResourceKey,
  canonicalResourceKey,
  createResourceTree,
  type ResourceKey,
  type ResourceTree,
  resourceAudience,
  type TokenCacheStore,
  validateResourceKey,
} from '../../src/lib/resource-tree';
import { FakeAuthProvider } from '../../src/test-helper/fake-provider';
import { InMemorySingleFlightCoordinator } from '../../src/test-helper/fake-single-flight-coordinator';
import { InMemoryTokenCacheStore } from '../../src/test-helper/fake-token-cache-store';
import { authProblems, testProblem } from './support';

const START = Temporal.Instant.from('2026-07-24T12:00:00Z');
const ZERO = Temporal.Duration.from({ seconds: 0 });
const ZINC_KEY = 'alcohol/lapras/zinc/api' as CanonicalResourceKey;
const ARGON_KEY = 'alcohol/lapras/argon/api' as CanonicalResourceKey;
const ZINC_AUDIENCE = 'https://api.zinc.alcohol.lapras.cluster.atomi.cloud';
const ARGON_AUDIENCE = 'https://api.argon.alcohol.lapras.cluster.atomi.cloud';
const PROBLEMS = authProblems().problems;

const zinc: ResourceKey = {
  platform: 'alcohol',
  landscape: 'lapras',
  service: 'zinc',
  resourceName: 'api',
};
const argon: ResourceKey = {
  platform: 'alcohol',
  landscape: 'lapras',
  service: 'argon',
  resourceName: 'api',
};

function registration(
  backendId: string,
  resources: readonly ResourceKey[],
  onboardingResource = resources[0] as ResourceKey,
): BackendRegistration {
  return { backendId, resources, onboardingResource };
}

function token(value: string, expiresAt = START.add({ minutes: 10 })): TokenResponse {
  return { token: value, expiresAt };
}

function fakeClock(initial = START) {
  let instant = initial;
  return {
    clock: { now: () => instant },
    set: (value: Temporal.Instant) => {
      instant = value;
    },
  };
}

interface TreeHarnessOptions {
  readonly bindings?: readonly BackendRegistration[];
  readonly provider?: FakeAuthProvider;
  readonly store?: TokenCacheStore;
  readonly time?: ReturnType<typeof fakeClock>;
  readonly concurrency?: number;
  readonly skew?: Temporal.Duration;
  readonly mapError?: (error: unknown) => Problem;
}

async function tree(options: TreeHarnessOptions = {}): Promise<ResourceTree> {
  const time = options.time ?? fakeClock();
  const skew = options.skew ?? ZERO;
  const tokenCache = await createSingleFlightCache<CanonicalResourceKey, TokenResponse>({
    coordinator: new InMemorySingleFlightCoordinator(),
    clock: time.clock,
    skew,
    ...(options.mapError === undefined ? {} : { mapError: options.mapError }),
  }).unwrap();
  return createResourceTree(options.provider ?? new FakeAuthProvider(), {
    bindings: options.bindings ?? [],
    store: options.store ?? new InMemoryTokenCacheStore(),
    tokenCache,
    clock: time.clock,
    problems: PROBLEMS,
    skew,
    ...(options.concurrency === undefined ? {} : { concurrency: options.concurrency }),
    ...(options.mapError === undefined ? {} : { mapError: options.mapError }),
  }).unwrap();
}

describe('ResourceTree construction and identity', () => {
  it('safe-parses resource values before producing exact canonical keys and audiences', async () => {
    // Arrange
    const invalid = { ...zinc, platform: 'Not_DNS' };

    // Act
    const actualKey = await canonicalResourceKey(zinc, PROBLEMS).unwrap();
    const actualAudience = await resourceAudience(zinc, PROBLEMS).unwrap();
    const invalidKey = canonicalResourceKey(invalid, PROBLEMS);
    const invalidAudience = resourceAudience(invalid, PROBLEMS);
    const defaultProblem = validateResourceKey(invalid);

    // Assert
    should(actualKey).equal(ZINC_KEY);
    should(actualAudience).equal(ZINC_AUDIENCE);
    should(await invalidKey.isErr()).be.true();
    should(await invalidAudience.isErr()).be.true();
    should((await defaultProblem.unwrapErr()).title).equal('Authentication resource configuration failed');
  });

  it('returns Problem Results for every invalid resource component without throwing', async () => {
    // Arrange
    const fields = ['platform', 'landscape', 'service', 'resourceName'] as const;

    // Act
    const results = fields.map(field => () => validateResourceKey({ ...zinc, [field]: 'Not_DNS' }, PROBLEMS));
    const valid = await validateResourceKey(zinc, PROBLEMS).unwrap();

    // Assert
    for (const result of results) {
      should(result).not.throw();
      should(await result().isErr()).be.true();
    }
    should(valid).deepEqual(zinc);
    should(Object.isFrozen(valid)).be.true();
  });

  it('constructs a ready immutable registry with no order-dependent registration step', async () => {
    // Arrange
    const mutableResource = { ...zinc };
    const mutableResources = [mutableResource];
    const mutableBinding = {
      backendId: 'zinc',
      resources: mutableResources,
      onboardingResource: mutableResource,
    };

    // Act
    const subject = await tree({ bindings: [mutableBinding] });
    mutableResource.service = 'argon';
    mutableResources[0] = argon;
    const actual = await subject.getBackend('zinc').unwrap();

    // Assert
    should(actual.resources[0]).deepEqual(zinc);
    should(actual.onboardingResource).deepEqual(zinc);
    should(subject.listBackends()).have.length(1);
    should(Object.isFrozen(subject.listBackends())).be.true();
    should(Object.isFrozen(actual)).be.true();
    should(Object.isFrozen(actual.resources)).be.true();
  });

  it('rejects invalid or duplicate backend bindings during construction as Problems', async () => {
    // Arrange
    const mapped = testProblem('invalid registration');
    const time = fakeClock();
    const tokenCache = await createSingleFlightCache<CanonicalResourceKey, TokenResponse>({
      coordinator: new InMemorySingleFlightCoordinator(),
      clock: time.clock,
      mapError: () => mapped,
    }).unwrap();
    const base = {
      store: new InMemoryTokenCacheStore(),
      tokenCache,
      clock: time.clock,
      problems: PROBLEMS,
      mapError: () => mapped,
    };
    const inputs = [
      [registration('', [zinc])],
      [registration('empty', [], zinc)],
      [registration('invalid', [{ ...zinc, service: 'UPPER' }])],
      [registration('mismatch', [zinc], argon)],
      [registration('duplicate-resource', [zinc, zinc], zinc)],
      [registration('same', [zinc]), registration('same', [argon])],
    ];

    // Act
    const results = inputs.map(bindings => () => createResourceTree(new FakeAuthProvider(), { ...base, bindings }));

    // Assert
    for (const result of results) {
      should(result).not.throw();
      should(await result().unwrapErr()).equal(mapped);
    }
  });

  it('requires an explicit cache store and validates concurrency without throwing', async () => {
    // Arrange
    const mapped = testProblem('invalid resource-tree options');
    const time = fakeClock();
    const tokenCache = await createSingleFlightCache<CanonicalResourceKey, TokenResponse>({
      coordinator: new InMemorySingleFlightCoordinator(),
      clock: time.clock,
      mapError: () => mapped,
    }).unwrap();
    const missingStore = () =>
      createResourceTree(new FakeAuthProvider(), {
        bindings: [],
        tokenCache,
        clock: time.clock,
        problems: PROBLEMS,
        mapError: () => mapped,
      });
    const invalidConcurrency = () =>
      createResourceTree(new FakeAuthProvider(), {
        bindings: [],
        store: new InMemoryTokenCacheStore(),
        tokenCache,
        clock: time.clock,
        problems: PROBLEMS,
        concurrency: 0,
        mapError: () => mapped,
      });

    // Act
    const missing = missingStore();
    const invalid = invalidConcurrency();

    // Assert
    should(missingStore).not.throw();
    should(invalidConcurrency).not.throw();
    should(await missing.unwrapErr()).equal(mapped);
    should(await invalid.unwrapErr()).equal(mapped);
  });

  it('returns Problems for malformed and unknown public backend ids', async () => {
    // Arrange
    const subject = await tree({ bindings: [registration('zinc', [zinc])] });

    // Act
    const malformed = subject.getBackend('UPPER');
    const unknown = subject.getBackend('argon');

    // Assert
    should(await malformed.isErr()).be.true();
    should(await unknown.isErr()).be.true();
  });
});

describe('ResourceTree token acquisition', () => {
  it('layers in-process single-flight over the explicit store with exact Temporal boundaries', async () => {
    // Arrange
    const time = fakeClock();
    const store = new InMemoryTokenCacheStore();
    const provider = new FakeAuthProvider({
      accessTokens: { [ZINC_AUDIENCE]: token('first', START.add({ minutes: 1 })) },
    });
    const firstTree = await tree({ provider, store, time, bindings: [registration('zinc', [zinc])] });

    // Act
    const concurrent = Array.from({ length: 12 }, () => firstTree.getToken(zinc).unwrap());
    const first = await Promise.all(concurrent);
    const stored = store.inspect(ZINC_KEY);
    const secondProvider = new FakeAuthProvider();
    const secondTree = await tree({ provider: secondProvider, store, time });
    const fromStore = await secondTree.getToken(zinc).unwrap();
    time.set(START.add({ minutes: 1 }));
    provider.setAccessToken(ZINC_AUDIENCE, token('second', START.add({ minutes: 2 })));
    const refreshed = await firstTree.getToken(zinc).unwrap();

    // Assert
    should(first.map(item => item.token)).deepEqual(Array(12).fill('first'));
    should(provider.accessTokenCalls).have.length(2);
    should(stored?.token).equal('first');
    should(fromStore.token).equal('first');
    should(secondProvider.accessTokenCalls).have.length(0);
    should(refreshed.token).equal('second');
  });

  it('returns resource validation, provider, malformed-token, and KV failures as Problems', async () => {
    // Arrange
    const providerFailure = testProblem('provider');
    const provider = new FakeAuthProvider();
    provider.enqueueAccessToken(ZINC_AUDIENCE, providerFailure);
    const subject = await tree({ provider });
    const storeFailure = testProblem('kv');
    const failingStore = new InMemoryTokenCacheStore();
    failingStore.setFailure(storeFailure);
    const malformedProvider = new FakeAuthProvider({
      accessTokens: {
        [ZINC_AUDIENCE]: { token: '', expiresAt: START.add({ minutes: 1 }) },
      },
    });

    // Act
    const invalidResource = subject.getToken({ ...zinc, service: 'INVALID' });
    const failedProvider = subject.getToken(zinc);
    const failedStore = (await tree({ provider, store: failingStore })).getToken(zinc);
    const malformed = (await tree({ provider: malformedProvider })).getToken(zinc);

    // Assert
    should(await invalidResource.isErr()).be.true();
    should(await failedProvider.unwrapErr()).equal(providerFailure);
    should(await failedStore.unwrapErr()).equal(storeFailure);
    should(await malformed.isErr()).be.true();
  });

  it('propagates an explicit KV set failure', async () => {
    // Arrange
    const storeFailure = testProblem('set failed');
    const provider = new FakeAuthProvider({
      accessTokens: { [ZINC_AUDIENCE]: token('value') },
    });
    const store: TokenCacheStore = {
      get: () => Ok(undefined),
      set: () => Err(storeFailure),
      delete: () => Ok(undefined),
    };
    const subject = await tree({ provider, store });

    // Act
    const actual = await subject.getToken(zinc).unwrapErr();

    // Assert
    should(actual).equal(storeFailure);
  });

  it('starts bounded batch acquisitions eagerly, deduplicates keys, and isolates backend failures', async () => {
    // Arrange
    const argonFailure = testProblem('argon failed');
    let started = 0;
    let announceStarted!: () => void;
    const bothStarted = new Promise<void>(resolve => {
      announceStarted = resolve;
    });
    let release!: () => void;
    const gate = new Promise<void>(resolve => {
      release = resolve;
    });
    const provider = new FakeAuthProvider();
    provider.enqueueAccessToken(ZINC_AUDIENCE, async () => {
      started += 1;
      if (started === 2) announceStarted();
      await gate;
      return token('zinc');
    });
    provider.enqueueAccessToken(ARGON_AUDIENCE, async () => {
      started += 1;
      if (started === 2) announceStarted();
      await gate;
      return argonFailure;
    });
    const subject = await tree({
      provider,
      concurrency: 2,
      bindings: [registration('zinc', [zinc]), registration('argon', [argon, zinc], argon)],
    });

    // Act
    const result = subject.fetchAllTokens();
    await bothStarted;
    const startedBeforeRelease = started;
    release();
    const batch = await result.unwrap();
    const zincBatch = subject.backendTokens(batch, 'zinc');
    const argonBatch = subject.backendTokens(batch, 'argon');

    // Assert
    should(startedBeforeRelease).equal(2);
    should(Object.keys(batch).sort()).deepEqual([ARGON_KEY, ZINC_KEY].sort());
    should((batch[ZINC_KEY] as TokenResponse).token).equal('zinc');
    should(isProblem(batch[ARGON_KEY])).be.true();
    should(provider.accessTokenCalls.filter(item => item === ZINC_AUDIENCE)).have.length(1);
    should(await zincBatch.isOk()).be.true();
    should(await argonBatch.unwrapErr()).equal(argonFailure);
  });

  it('fetches a complete backend batch and reports unknown or incomplete batches as Problems', async () => {
    // Arrange
    const provider = new FakeAuthProvider({
      accessTokens: { [ZINC_AUDIENCE]: token('zinc') },
    });
    const subject = await tree({ provider, bindings: [registration('zinc', [zinc])] });

    // Act
    const fetched = await subject.fetchBackendTokens('zinc').unwrap();
    const unknown = subject.backendTokens({}, 'missing');
    const incomplete = subject.backendTokens({}, 'zinc');
    const empty = await (await tree()).fetchAllTokens().unwrap();

    // Assert
    should(fetched[ZINC_KEY]?.token).equal('zinc');
    should(await unknown.isErr()).be.true();
    should(await incomplete.isErr()).be.true();
    should(empty).deepEqual({});
  });
});

describe('ResourceTree invalidation', () => {
  it('invalidates one key and all keys through the explicit store', async () => {
    // Arrange
    const provider = new FakeAuthProvider({ accessTokens: { [ZINC_AUDIENCE]: token('one') } });
    const store = new InMemoryTokenCacheStore();
    const subject = await tree({ provider, store, bindings: [registration('zinc', [zinc])] });
    await subject.getToken(zinc).unwrap();

    // Act
    const one = subject.invalidate(zinc);
    await one.unwrap();
    const afterOne = store.inspect(ZINC_KEY);
    const invalid = subject.invalidate({ ...zinc, landscape: 'INVALID' });
    await subject.getToken(zinc).unwrap();
    const all = subject.invalidateAll();

    // Assert
    should(await one.isOk()).be.true();
    should(afterOne).be.undefined();
    should(await invalid.isErr()).be.true();
    should(await all.isOk()).be.true();
    should(store.inspect(ZINC_KEY)).be.undefined();
  });

  it('deletes every immutable binding key when a store has no bulk clear and propagates failures', async () => {
    // Arrange
    const deleted: CanonicalResourceKey[] = [];
    const failure = testProblem('delete failed');
    let fail = false;
    const store: TokenCacheStore = {
      get: () => Ok(undefined),
      set: () => Ok(undefined),
      delete: key => {
        deleted.push(key);
        return fail ? Err(failure) : Ok(undefined);
      },
    };
    const subject = await tree({
      store,
      bindings: [registration('zinc', [zinc, argon], zinc)],
    });

    // Act
    const first = subject.invalidateAll();
    await first.unwrap();
    fail = true;
    const second = subject.invalidateAll();
    const single = subject.invalidate(zinc);

    // Assert
    should(deleted.slice(0, 2).sort()).deepEqual([ARGON_KEY, ZINC_KEY].sort());
    should(await second.unwrapErr()).equal(failure);
    should(await single.unwrapErr()).equal(failure);
  });
});
