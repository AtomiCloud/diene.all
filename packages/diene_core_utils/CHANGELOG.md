# Changelog

All notable changes to this package are documented here. Releases are managed
from conventional commits by the repository release workflow.

## 1.0.0

- Add the identity surface: `slugify` (NFKD, combining-mark removal, ASCII kebab,
  total and idempotent), `namespacedKey` (`Result<String>`, naming the offending
  `NamespacedKeyField` on failure), and `fuzzyIncludes`.
- Add the C0 §3 layered-configuration mechanics: `JsonObject`, `deepClone`,
  `deepMerge`, `deepMergeAll`, `canonicalConfigKey`, `configKeysMatch`,
  `coerceEnvironmentScalar`, and `environmentToNestedMap`. Key matching is case-
  and separator-insensitive (including the environment prefix), the base layer's
  key spelling wins, `__` splits paths, all-digit components build lists, blank
  values mean UNSET, and neither JSON nor comma-separated strings are ever decoded
  into collections.
- Add deterministic config projection: `isJsonObject`, `stableConfig`, and
  `stableConfigObject`, sorting keys at every depth while preserving list order,
  and reporting circular input as `record_unprojectable` instead of recursing.
- Add the C0 §1 temporal wire forms: `WireDate`, `WireTime`, `IsoDuration`, and
  `IanaTimezone` value types with `Result`-returning `parse`/`of` members;
  `formatRfc3339Utc`; the STRICT `parseRfc3339Utc` (only the `Z` designator, so
  one canonical spelling exists); the `normalizeRfc3339ToUtc` boundary ingress for
  offset-carrying instants; and the `WireCodec` facade.
- Validate timezone identifiers by exact membership in a vendored, digest-pinned
  official IANA release (`2026b`, 598 identifiers) rather than a lexical shape
  check or host `/usr/share/zoneinfo` data, so the answer is reproducible.
- Export the shared, version-pinned C0 §1 temporal contract as the
  `c0_temporal.dart` sub-library, so every Diene Dart package drives its temporal
  conformance from one `c0TemporalContract` value instead of restating cases.
- Add `Vfs`-seam helpers over the published `diene_interfaces` interface type:
  `readVfsText`, `writeVfsText`, `readOptionalVfsText`, `ConfigLayer`, and
  `loadConfigLayers`. The package imports neither `dart:io` nor Flutter, so it runs
  on the VM, on the web, and in Flutter, and a seam failure is propagated unchanged
  with its own status and `recoverable` flag intact.
- Add `sleep` and `mapWithConcurrency`, the latter preserving input order, holding
  a real concurrency bound, and resolving to the lowest failing index so the
  outcome never depends on completion order.
- Report every expected failure as a `Result` value carrying the canonical RFC 9457
  `Problem` from `diene_problems`, with the `type` URI minted only by the single
  C0 §2 builder (`UtilName`, `UtilErrorCode`, `utilProblem`, `utilFailure`,
  `invalidUtilInput`, `invalidWireFormat`).
- Ship no `test_helper.dart`: every member is a pure function or a pass-through
  over an injected seam, so there is nothing to fake and no assertion a consumer
  would repeat. The shipped `diene-core-utils-usage` skill carries the meta
  convention and explains how to add one should that change.
