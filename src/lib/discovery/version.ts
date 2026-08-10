import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { staleVersion } from './errors';
import type { DiscoveryError, VersionLedger } from './types';

/**
 * A mutable, per-document monotonic version ledger. Keys are per-doc (A/B/C, or
 * finer) so monotonicity is enforced independently — never global.
 */
export interface MutableVersionLedger extends VersionLedger {
  /**
   * Accept `incoming` for `key` iff it is not older than the newest seen. An
   * equal version is idempotently accepted (cheap 304 / stale-while-revalidate
   * refresh); a strictly older version is rejected. On acceptance the newest is
   * advanced and the accepted version returned.
   */
  accept(key: string, incoming: number): Result<number, DiscoveryError>;
}

/** Create an empty version ledger. */
export const createVersionLedger = (): MutableVersionLedger => {
  const newest = new Map<string, number>();

  return {
    seen(key) {
      return newest.get(key);
    },
    accept(key, incoming) {
      const current = newest.get(key);
      if (current !== undefined && incoming < current) {
        return Err(staleVersion(key, current, incoming));
      }
      newest.set(key, incoming);
      return Ok(incoming);
    },
  };
};
