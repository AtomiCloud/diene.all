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
    const probe = namespacedKey('doctor', 'probe');
    await this.store.set(probe, 'ok');
    return (await this.store.get(probe)) === 'ok';
  }
}
