import type { IKeyValueStore, IProgressReporter } from './interfaces';
import { namespacedKey } from './slug';

/** Domain logic over the key-value store — zero IO beyond the injected ports. */
export class KvService {
  constructor(private readonly store: IKeyValueStore) {}

  async setValue(namespace: string, key: string, value: string, ttlSeconds?: number): Promise<string> {
    const composed = namespacedKey(namespace, key);
    await this.store.set(composed, value, ttlSeconds);
    return composed;
  }

  async getValue(namespace: string, key: string): Promise<{ composed: string; value: string | null }> {
    const composed = namespacedKey(namespace, key);
    return { composed, value: await this.store.get(composed) };
  }

  async seed(namespace: string, count: number, progress: IProgressReporter): Promise<void> {
    progress.start(count);
    try {
      for (let i = 1; i <= count; i++) {
        await this.store.set(namespacedKey(namespace, `sample-${i}`), `value-${i}`);
        progress.tick();
      }
    } finally {
      progress.stop();
    }
  }
}
