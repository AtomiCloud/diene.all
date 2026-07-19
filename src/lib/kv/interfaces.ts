/** Ports the domain depends on — adapters implement these (dependency direction points inward). */

export interface IKeyValueStore {
  /** Persist `value` under `key`, optionally expiring after `ttlSeconds`. */
  set(key: string, value: string, ttlSeconds?: number): Promise<void>;
  get(key: string): Promise<string | null>;
  close(): Promise<void>;
}

/** Per-invocation progress reporting (implemented by the terminal progress-bar adapter). */
export interface IProgressReporter {
  start(total: number): void;
  tick(): void;
  stop(): void;
}

/** System shell port (implemented by the Bun Shell adapter). */
export interface IShell {
  platform(): Promise<string>;
}
