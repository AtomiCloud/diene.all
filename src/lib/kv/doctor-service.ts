import type { IKeyValueStore, IShell } from './interfaces';
import { namespacedKey } from './slug';

/** Backend + environment health checks. */
export class DoctorService {
  constructor(
    private readonly store: IKeyValueStore,
    private readonly shell: IShell,
  ) {}

  async platform(): Promise<string> {
    return this.shell.platform();
  }

  /** Round-trips a probe key; true when the backend answers with the written value. */
  async probeBackend(): Promise<boolean> {
    const probe = namespacedKey('doctor', `probe-${crypto.randomUUID()}`);
    // TTL is a cleanup backstop; the normal path removes the unique key immediately.
    await this.store.set(probe, 'ok', 30);
    try {
      return (await this.store.get(probe)) === 'ok';
    } finally {
      // Cleanup must never mask a backend error; the TTL bounds any failed deletion.
      await this.store.delete(probe).catch(() => undefined);
    }
  }
}
