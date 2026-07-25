import { plugin } from 'bun';

/**
 * Int-tier preload: neutralize React's `server-only` / `client-only` marker
 * packages so server adapters (`src/adapters/auth/*`, `src/adapters/server-config`)
 * and `'use client'` adapters can both be imported by the same bun test runner.
 *
 * The markers exist to fail the Next.js bundler when a module crosses the
 * server/client boundary — that boundary is enforced at BUILD time by
 * `bunx next build` and by `scripts/validate/pure-renderer.ts`, not at test
 * time. Under bun there is no RSC graph, so the markers would simply make every
 * server adapter unimportable and leave the int ledger permanently incomplete.
 */
plugin({
  name: 'rsc-marker-shim',
  setup(build) {
    for (const marker of ['server-only', 'client-only']) {
      build.module(marker, () => ({ exports: {}, loader: 'object' }));
    }
  },
});
