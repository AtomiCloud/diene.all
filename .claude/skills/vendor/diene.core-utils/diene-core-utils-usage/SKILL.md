---
name: diene-core-utils-usage
description: Use when consuming @atomicloud/diene.core-utils for deterministic utilities, explicit-root filesystem paths, or C0 Temporal wire codecs.
---

Import from `@atomicloud/diene.core-utils`. Use `slugify` for identifiers and
handle both branches of Result-returning `namespacedKey`; validation is not an
exceptional throw path. Use `sleep`/`noop` intentionally, `fuzzyIncludes` only
for case-insensitive substring search, and `mapWithConcurrency` with a bounded
limit chosen for the downstream resource.

Use `isRecord` before record access, `stableConfig` before deterministic
comparison/hash input, `sha256` for digests, and `unique` for deduplication.
Filesystem helpers require an explicit root: use `safeJoin(root, ...)`, never an
implicit current working directory.

At a transport boundary use the `parseWire*`/`formatWire*` Temporal codecs only:
date `YYYY-MM-DD`, time `HH:mm:ss`, UTC RFC3339 instant, ISO8601 duration, and
IANA timezone identifier. Keep locale display formatting outside the wire.

Read [patterns.md](patterns.md) for examples and the future-TestHelper rule. This
pure-value package has TestHelper=NO: do not add a helper merely for convenience.
