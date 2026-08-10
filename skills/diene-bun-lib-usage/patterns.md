# @atomicloud/diene.bun-lib — patterns

## Do

- Import from the package root (`@atomicloud/diene.bun-lib`); let the exports map
  pick the right module and declaration file for your module system.
- Depend on the published API surface only — `buildSampleKey`,
  `createRedisStore`, `persistSample`, and the `IKeyValueStore` /
  `RedisConnection` types.
- Provide your own `RedisConnection` and close the store you create.

## Don't

- Don't deep-import into `dist/` internals; only the root entry is public.
- Don't rely on side effects at import time — the package is `sideEffects: false`.

## TestHelper

This library ships **no** TestHelper: its surface is pure functions plus a thin
Redis-backed store, so consumers fake the `IKeyValueStore` port directly in
their own tests. If a real, repeated consumer pain later appears (for example a
shared fake store or an assertion helper every consumer rewrites), add it as a
subpath export `@atomicloud/diene.bun-lib/test-helper`, declare any
helper-only dependency as an **optional peer dependency** (never a regular
dependency), prove it through the `meta` test tier, and document it here.
