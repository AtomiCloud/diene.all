import type { CacheSlot, SingleFlightCoordinator } from '../lib/cache';

export class InMemorySingleFlightCoordinator<K, V> implements SingleFlightCoordinator<K, V> {
  readonly values = new Map<K, CacheSlot<V>>();

  get size(): number {
    return this.values.size;
  }

  get(key: K): CacheSlot<V> | undefined {
    return this.values.get(key);
  }

  set(key: K, slot: CacheSlot<V>): void {
    this.values.set(key, slot);
  }

  delete(key: K): boolean {
    return this.values.delete(key);
  }

  clear(): void {
    this.values.clear();
  }
}
