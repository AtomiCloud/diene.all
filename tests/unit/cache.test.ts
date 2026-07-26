import { describe, it } from 'bun:test';
import { Err, Ok, Res } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import should from 'should';
import { type CacheEntry, createSingleFlightCache, type SingleFlightCoordinator } from '../../src/lib/cache';
import { InMemorySingleFlightCoordinator } from '../../src/test-helper/fake-single-flight-coordinator';
import { testProblem } from './support';

const START = Temporal.Instant.from('2026-07-24T12:00:00Z');
const SECOND = Temporal.Duration.from({ seconds: 1 });

function fakeClock(initial = START) {
  let instant = initial;
  return {
    clock: { now: () => instant },
    advance: (duration: Temporal.Duration) => {
      instant = instant.add(duration);
    },
    set: (value: Temporal.Instant) => {
      instant = value;
    },
  };
}

async function subject<K, V>(
  coordinator: SingleFlightCoordinator<K, V> = new InMemorySingleFlightCoordinator<K, V>(),
  clock = fakeClock().clock,
  mapError?: (error: unknown) => ReturnType<typeof testProblem>,
) {
  return createSingleFlightCache<K, V>({
    coordinator,
    clock,
    skew: Temporal.Duration.from({ seconds: 10 }),
    mapError,
  }).unwrap();
}

describe('SingleFlightCache', () => {
  it('shares exactly one in-flight fetch across concurrent callers and then hits the cache', async () => {
    // Arrange
    let resolve!: (value: CacheEntry<string>) => void;
    const gate = new Promise<CacheEntry<string>>(done => {
      resolve = done;
    });
    let calls = 0;
    const cache = await subject<string, string>();
    const fetcher = () => {
      calls += 1;
      return Ok<CacheEntry<string>, never>(gate);
    };

    // Act
    const results = Array.from({ length: 20 }, () => cache.get('token', fetcher));
    resolve({ value: 'shared', expiresAt: START.add({ minutes: 1 }) });
    const actual = await Promise.all(results.map(result => result.unwrap()));
    const cached = await cache.get('token', fetcher).unwrap();

    // Assert
    should(actual).deepEqual(Array(20).fill('shared'));
    should(calls).equal(1);
    should(cached).equal('shared');
    should(cache.peek('token')?.value).equal('shared');
  });

  it('refreshes at the exact Temporal expiry-minus-skew boundary', async () => {
    // Arrange
    const time = fakeClock();
    let calls = 0;
    const cache = await subject<string, number>(new InMemorySingleFlightCoordinator(), time.clock);
    const fetcher = () => Ok({ value: ++calls, expiresAt: START.add(Temporal.Duration.from({ seconds: 100 })) });

    // Act
    const first = await cache.get('key', fetcher).unwrap();
    time.set(START.add(Temporal.Duration.from({ seconds: 89, milliseconds: 999 })));
    const beforeBoundary = await cache.get('key', fetcher).unwrap();
    time.advance(Temporal.Duration.from({ milliseconds: 1 }));
    const atBoundary = await cache.get('key', fetcher).unwrap();

    // Assert
    should(first).equal(1);
    should(beforeBoundary).equal(1);
    should(atBoundary).equal(2);
    should(calls).equal(2);
  });

  it('clears failed flights so every concurrent caller sees the failure and a later caller retries', async () => {
    // Arrange
    const failure = testProblem();
    let calls = 0;
    const cache = await subject<string, string>();
    const fetcher = () => {
      calls += 1;
      return calls === 1
        ? Err<CacheEntry<string>, typeof failure>(failure)
        : Ok({ value: 'ok', expiresAt: START.add({ minutes: 1 }) });
    };

    // Act
    const first = cache.get('key', fetcher);
    const shared = cache.get('key', fetcher);
    const firstFailure = await first.unwrapErr();
    const sharedFailure = await shared.unwrapErr();
    const retried = await cache.get('key', fetcher).unwrap();

    // Assert
    should(firstFailure).equal(failure);
    should(sharedFailure).equal(failure);
    should(retried).equal('ok');
    should(calls).equal(2);
  });

  it('maps synchronous fetcher throws and rejected Result internals to Problems', async () => {
    // Arrange
    const mapped = testProblem('mapped');
    const cache = await subject<string, string>(new InMemorySingleFlightCoordinator(), fakeClock().clock, () => mapped);

    // Act
    const synchronous = await cache
      .get('sync', () => {
        throw new Error('sync');
      })
      .unwrapErr();
    const asynchronous = await cache.get('async', () => Res.fromSerial(Promise.reject(new Error('async')))).unwrapErr();

    // Assert
    should(synchronous).equal(mapped);
    should(asynchronous).equal(mapped);
  });

  it('does not repopulate a key cleared during its flight', async () => {
    // Arrange
    let resolve!: (value: CacheEntry<string>) => void;
    const gate = new Promise<CacheEntry<string>>(done => {
      resolve = done;
    });
    const cache = await subject<string, string>();

    // Act
    const result = cache.get('key', () => Ok<CacheEntry<string>, never>(gate));
    const deleted = cache.delete('key');
    resolve({ value: 'value', expiresAt: START.add({ minutes: 1 }) });
    const actual = await result.unwrap();

    // Assert
    should(deleted).be.true();
    should(actual).equal('value');
    should(cache.peek('key')).be.undefined();
  });

  it('validates construction and cache entries through Problem Results without throwing', async () => {
    // Arrange
    const mapped = testProblem('invalid cache input');
    const invalidConstruction = () =>
      createSingleFlightCache<string, string>({
        clock: fakeClock().clock,
        skew: Temporal.Duration.from({ months: 1 }),
        mapError: () => mapped,
      });
    const cache = await subject<string, string>(new InMemorySingleFlightCoordinator(), fakeClock().clock, () => mapped);

    // Act
    const construction = invalidConstruction();
    const defaultConstruction = createSingleFlightCache<string, string>({});
    const invalidSet = cache.set('invalid', {
      value: 'value',
      expiresAt: 'not-an-instant' as unknown as Temporal.Instant,
    });
    const invalidFetch = cache.get('invalid-fetch', () =>
      Ok({ value: 'value', expiresAt: 'not-an-instant' as unknown as Temporal.Instant }),
    );

    // Assert
    should(invalidConstruction).not.throw();
    should(await construction.unwrapErr()).equal(mapped);
    should((await defaultConstruction.unwrapErr()).title).equal('Cache refresh failed');
    should(await invalidSet.unwrapErr()).equal(mapped);
    should(await invalidFetch.unwrapErr()).equal(mapped);
  });

  it('exposes Result-typed set plus nonfallible coordinator inspection and invalidation', async () => {
    // Arrange
    const coordinator = new InMemorySingleFlightCoordinator<string, number>();
    const cache = await subject<string, number>(coordinator);
    const entry = { value: 4, expiresAt: START.add(SECOND) };

    // Act
    const set = cache.set('other', entry);
    const peeked = cache.peek('other');
    const deleted = cache.delete('other');
    cache.set('one', entry);
    cache.set('two', entry);
    cache.clear();

    // Assert
    should(await set.isOk()).be.true();
    should(peeked).deepEqual(entry);
    should(deleted).be.true();
    should(cache.delete('missing')).be.false();
    should(cache.size).equal(0);
    should(cache.peek('missing')).be.undefined();
  });
});
