import type { ConfigRecord } from './merge.js';

/** A flat environment record: variable name → value (or `undefined` when unset). */
export type EnvRecord = Record<string, string | undefined>;

/**
 * Where the loader draws its four tiers from. Real IO implementations (YAML
 * files, `process.env`) live in `src/adapters`; in-memory fakes live in the
 * TestHelper. The loader itself is source-agnostic.
 */
export interface ConfigSource {
  /** Tier 1 — base YAML: the full-defaults object. */
  base(): Promise<ConfigRecord>;
  /** Tier 2 — the sparse landscape overlay for `landscape` (`{}` when none). */
  overlay(landscape: string): Promise<ConfigRecord>;
  /** Tier 3 — build-time injected env, frozen at build (`{}` when none). */
  buildTimeEnv(): Promise<EnvRecord>;
  /** Tier 4 — runtime env (`process.env`), applied LAST. */
  runtimeEnv(): Promise<EnvRecord>;
}
