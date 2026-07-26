---
name: diene-core-utils-usage
description: Use when working with slugs, namespaced keys, layered configuration merges, environment coercions, or C0 ISO 8601 / RFC 3339 / IANA timezone wire formats in Dart via the diene_core_utils package.
---

# diene_core_utils usage

Pure Dart utilities. Every fallible member returns `Result` from `diene_result`
carrying a `Problem` from `diene_problems`; nothing throws to report an expected
failure, so never wrap a call here in `try`/`catch`.

The package imports neither `dart:io` nor Flutter. It reaches the filesystem only
through the injected `Vfs` interface from `diene_interfaces`, so it runs unchanged
on the VM, on the web, and in Flutter.

## Import

```dart
import 'package:diene_core_utils/diene_core_utils.dart';
// The shared C0 §1 temporal contract only:
import 'package:diene_core_utils/c0_temporal.dart';
```

## Rules

1. **Never hand-roll a slug, a config merge, or a date format.** These exist to
   kill bespoke variants; a second implementation is a review failure.
2. **Handle the `Result`.** Use `match`, `andThen`, or `unwrapOr`. Reserve
   `unwrap()` for tests and for a value you have already proven `isOk`.
3. **Money and exact decimals never go through `coerceEnvironmentScalar`.** Per
   C0 §1 they travel as decimal STRINGS end to end. The decimal branch produces a
   lossy `double` for config numerics only (ratios, timeouts, thresholds).
4. **`parseRfc3339Utc` accepts only the `Z` designator** — `+00:00` is rejected
   even though it denotes the same instant. Normalise offset-carrying input once,
   at the boundary, with `normalizeRfc3339ToUtc`.
5. **Lists in configuration come only from indexed keys** (`FOO__0`, `FOO__1`).
   Never encode a list as JSON or as a comma-separated string; neither is decoded.
6. **A blank environment value means UNSET**, not empty-string and not null. It is
   omitted from the layer, so it cannot erase a base value.
7. **Take `Vfs` as a parameter**, never a concrete filesystem. That is what makes
   your own code testable with `InMemoryVfs`.
8. **Do not re-wrap a `Vfs` failure.** It already carries a C0 §2 envelope with its
   own status and `recoverable` flag; a second envelope buries the real cause.

## Quick reference

| Need                              | Member                                                       |
| --------------------------------- | ------------------------------------------------------------ |
| Deterministic kebab slug          | `slugify(String) -> String` (total)                          |
| `namespace:key` identifier        | `namespacedKey(String, String) -> Result<String>`            |
| Case-insensitive contains         | `fuzzyIncludes(haystack, needle) -> bool`                    |
| Merge config layers               | `deepMergeAll(Iterable<JsonObject>) -> JsonObject`           |
| Merge two layers                  | `deepMerge(base, overlay) -> JsonObject`                     |
| Compare key spellings             | `configKeysMatch`, `canonicalConfigKey`                      |
| Coerce one env value              | `coerceEnvironmentScalar(String) -> Object?`                 |
| Env vars to nested config         | `environmentToNestedMap(map, prefix:) -> Result<JsonObject>` |
| Hashable/diffable config          | `stableConfig`, `stableConfigObject`                         |
| Calendar date                     | `WireDate.parse` / `WireDate.of`                             |
| Wall-clock time                   | `WireTime.parse` / `WireTime.of`                             |
| Duration                          | `IsoDuration.parse`                                          |
| Timezone id                       | `IanaTimezone.parse`, `isIanaTimeZone`                       |
| Instant, strict                   | `parseRfc3339Utc`, `formatRfc3339Utc`                        |
| Instant, offset ingress           | `normalizeRfc3339ToUtc`                                      |
| All temporal codecs in one object | `const WireCodec()`                                          |
| Read/write config text            | `readVfsText`, `writeVfsText`, `readOptionalVfsText`         |
| Load a layer ladder               | `loadConfigLayers(Vfs, List<ConfigLayer>)`                   |
| Wait                              | `sleep(Duration) -> Future<Result<void>>`                    |
| Bounded parallel map              | `mapWithConcurrency(items, bound, mapper)`                   |
| Shared C0 temporal vectors        | `c0TemporalContract` (from `c0_temporal.dart`)               |

See `patterns.md` for worked examples, the failure vocabulary, and how to write
this package's TestHelper if one is ever needed.
