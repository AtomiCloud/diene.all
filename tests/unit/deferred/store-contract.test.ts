import { Temporal } from '@js-temporal/polyfill';
import { describeDeferredStoreContract } from '../../contract/deferred-store-contract';
import { FakeClock, InMemoryDeferredStore } from './support';

const START = Temporal.Instant.from('2026-07-24T12:00:00Z');

// A fresh fake clock per test drives the in-memory reference through the shared
// C0 §7 store contract with no real time.
let clock = new FakeClock(START);

describeDeferredStoreContract('InMemoryDeferredStore (reference)', {
  makeStore: () => {
    clock = new FakeClock(START);
    return new InMemoryDeferredStore(clock);
  },
  now: () => clock.now(),
  expire: async (ttl: Temporal.Duration) => {
    clock.advance(ttl.add({ seconds: 1 }));
  },
});
