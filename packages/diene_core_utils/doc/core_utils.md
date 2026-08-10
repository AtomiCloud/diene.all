# diene_core_utils

Pure Dart utilities shared by the Diene Dart family: deterministic identity
strings, the C0 §3 layered-configuration mechanics, and the C0 §1 temporal wire
forms.

Every fallible member returns `Result<T>` from `package:diene_result`, with the
canonical RFC 9457 `Problem` envelope from `package:diene_problems` as its error
channel. Nothing in this library throws to report an expected failure.

## Contract

### Identity

| Member          | Signature                                            | Notes                                                                                                                                                      |
| --------------- | ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `slugify`       | `String slugify(String)`                             | NFKD, combining-mark removal, lowercase, collapse non-ASCII-alphanumeric runs to `-`, strip edge hyphens. Total: unmappable input yields `''`. Idempotent. |
| `namespacedKey` | `Result<String> namespacedKey(String, String)`       | Slugifies both parts and joins with `:`. A part that slugifies to empty fails with `slug_invalid_input` naming the `NamespacedKeyField`.                   |
| `fuzzyIncludes` | `bool fuzzyIncludes(String haystack, String needle)` | Case-insensitive substring test; an empty needle is always contained.                                                                                      |

### Configuration (C0 §3)

| Member                    | Signature                                                                                  | Notes                                                                                                                                                 |
| ------------------------- | ------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `JsonObject`              | `typedef Map<String, Object?>`                                                             | The JSON-like config shape used throughout.                                                                                                           |
| `deepClone`               | `Object? deepClone(Object?)`                                                               | Rebuilds maps and lists; shares no mutable structure.                                                                                                 |
| `deepMerge`               | `JsonObject deepMerge(JsonObject base, JsonObject overlay)`                                | Maps merge recursively; lists and scalars replace. Keys match through `canonicalConfigKey`, and the **base layer's spelling wins** as the output key. |
| `deepMergeAll`            | `JsonObject deepMergeAll(Iterable<JsonObject>)`                                            | The precedence ladder itself: `base → landscape → --dart-define` is this fold in that order.                                                          |
| `canonicalConfigKey`      | `String canonicalConfigKey(String)`                                                        | Strips `-`/`_`, lowercases. `display-name`, `display_name`, `displayName`, `DisplayName` all fold together.                                           |
| `configKeysMatch`         | `bool configKeysMatch(String, String)`                                                     | Canonical-form equality.                                                                                                                              |
| `coerceEnvironmentScalar` | `Object? coerceEnvironmentScalar(String)`                                                  | Blank → `null` (UNSET); `true`/`false` any case → `bool`; safe ints → `int`; decimals/exponents → `double`; everything else stays `String`.           |
| `environmentToNestedMap`  | `Result<JsonObject> environmentToNestedMap(Map<String, String>, {required String prefix})` | `__` splits the path, all-digit components build lists, blank values are omitted, `prefix` matches case-insensitively.                                |
| `isJsonObject`            | `bool isJsonObject(Object?)`                                                               | Narrows to a `String`-keyed map.                                                                                                                      |
| `stableConfig`            | `Result<Object?> stableConfig(Object?)`                                                    | Sorts object keys at every depth, preserves list order. Safe to hash or diff. Cyclic input → `record_unprojectable`.                                  |
| `stableConfigObject`      | `Result<JsonObject> stableConfigObject(JsonObject)`                                        | Same, typed for a merged configuration.                                                                                                               |

**Money and exact decimals do not go through `coerceEnvironmentScalar`.** Per C0
§1 they travel as decimal STRINGS end to end; the decimal branch here produces a
`double` for ergonomic config numerics (ratios, timeouts, thresholds) and is
lossy by design. Integers beyond the IEEE-754 safe range are preserved as strings
for the same reason.

### C0 §1 temporal wire forms

| Member                  | Signature                                                        | Notes                                                                                                                                          |
| ----------------------- | ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `WireDate`              | `Result<WireDate> WireDate.parse(String)` / `.of(int, int, int)` | `YYYY-MM-DD`. Validates the real calendar: `2026-02-30` cannot be represented. Year `1..9999`.                                                 |
| `WireTime`              | `Result<WireTime> WireTime.parse(String)` / `.of(int, int, int)` | `HH:mm:ss`. No leap second.                                                                                                                    |
| `IsoDuration`           | `Result<IsoDuration> IsoDuration.parse(String)`                  | ISO 8601 designation kept verbatim (decimal comma normalised to a point). Calendar units are NOT converted — `Y`/`M`/`W` have no fixed length. |
| `IanaTimezone`          | `Result<IanaTimezone> IanaTimezone.parse(String)`                | Exact membership in the vendored IANA release, not a shape check.                                                                              |
| `isIanaTimeZone`        | `bool isIanaTimeZone(String)`                                    | The raw predicate. 598 identifiers from release `2026b`.                                                                                       |
| `ianaTimeZoneRelease`   | `const String`                                                   | `'2026b'`.                                                                                                                                     |
| `formatRfc3339Utc`      | `Result<String> formatRfc3339Utc(DateTime)`                      | Converts to UTC and renders the canonical `Z` form.                                                                                            |
| `parseRfc3339Utc`       | `Result<DateTime> parseRfc3339Utc(String)`                       | **Strict**: only the `Z` designator. `+00:00` is rejected.                                                                                     |
| `normalizeRfc3339ToUtc` | `Result<String> normalizeRfc3339ToUtc(String)`                   | The ingress helper: accepts an offset designator once, at the boundary, and returns bytes `parseRfc3339Utc` accepts forever after.             |
| `WireCodec`             | `const WireCodec()`                                              | Facade over all of the above, for consumers that prefer injecting one object.                                                                  |

Why `parseRfc3339Utc` rejects `+00:00` even though it denotes the same instant as
`Z`: C0 §1 fixes ONE canonical spelling so two services can compare wire bytes.
Accepting equivalent spellings would reintroduce exactly the format drift this
surface exists to kill. Data arriving with an offset goes through
`normalizeRfc3339ToUtc` at the boundary.

### The shared C0 temporal contract

`package:diene_core_utils/c0_temporal.dart` exports `c0TemporalContract`, the
single version-pinned set of C0 §1 temporal vectors for the whole Dart family.
Downstream packages drive their own conformance from this value instead of
restating cases that would drift apart. Its provenance pins the C0 source
document, the official IANA release, the archive digest, and a
`contentSha256` over the vectors themselves, so a silent vector edit reddens
`test/conformance/c0_temporal_test.dart`.

### The `Vfs` seam

| Member                | Signature                                                                                                              |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `readVfsText`         | `Future<Result<String>> readVfsText(Vfs, String)`                                                                      |
| `writeVfsText`        | `Future<Result<void>> writeVfsText(Vfs, String, String)`                                                               |
| `readOptionalVfsText` | `Future<Result<String?>> readOptionalVfsText(Vfs, String)`                                                             |
| `ConfigLayer`         | `const ConfigLayer({required String path, required Result<JsonObject> Function(String) parse, bool optional = false})` |
| `loadConfigLayers`    | `Future<Result<JsonObject>> loadConfigLayers(Vfs, List<ConfigLayer>)`                                                  |

These are the only members that touch the outside world, and they do it through
the **injected** `Vfs` interface from `package:diene_interfaces` — never
`dart:io`. Consequences worth knowing:

- The package runs unchanged on the VM, the web, and Flutter.
- Every one of these members is testable against
  `package:diene_interfaces/test_helper.dart`'s `InMemoryVfs` with no host
  filesystem.
- A `Vfs` failure is propagated **unchanged**, so the seam's own envelope (and
  its `recoverable` flag) survives rather than being buried under a second one.
- `ConfigLayer.parse` is injected because this package ships no YAML or JSON
  parser. The format is the consumer's choice; the PRECEDENCE and MERGE semantics
  are C0 §3 and belong here.
- `loadConfigLayers` reports `vfs_invalid_input` when no layer was present at all,
  because an empty configuration is a misconfiguration rather than a valid
  outcome.

### Problem vocabulary

`UtilName` (`slug`, `coercion`, `record`, `wire`, `concurrency`, `timing`, `vfs`)
× `UtilErrorCode` (`invalid_input`, `invalid_format`, `conflict`,
`unprojectable`, `delegated`) compose the problem id. Every `type` URI is minted
by `problemTypeUri` from `package:diene_problems` — the single C0 §2 builder — at
contract version `v1`. `recoverable` is always `false` here: every failure this
library reports is a deterministic function of its input, so retrying the
identical call cannot change the outcome.

### Concurrency and waiting

| Member               | Signature                                                                                           | Notes                                                                                                                                                                      |
| -------------------- | --------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sleep`              | `Future<Result<void>> sleep(Duration)`                                                              | A negative duration fails as a value and schedules no timer.                                                                                                               |
| `mapWithConcurrency` | `Future<Result<List<R>>> mapWithConcurrency<T, R>(Iterable<T>, int, Future<Result<R>> Function(T))` | Preserves INPUT order; at most `concurrency` calls in flight; work is pulled, not pushed. The LOWEST failing index wins, so the outcome never depends on completion order. |

## Parity with `lib/bun/core-utils`

The bun sibling is the surface-parity reference. Deltas are deliberate; an
undocumented delta is a review failure.

| bun member                                                                   | dart                                                             | Rationale                                                                                                                                                                                                                                                                                                                                                           |
| ---------------------------------------------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `slugify`                                                                    | `slugify`                                                        | Same transform. Dart uses `package:unorm_dart` for NFKD (the SDK has no Unicode normalisation).                                                                                                                                                                                                                                                                     |
| `namespacedKey`                                                              | `namespacedKey`                                                  | bun returns `Result<string, NamespacedKeyValidationError>`; dart's `Result` fixes its error channel to `Problem`, so the validation detail moves into `data.field` as a `NamespacedKeyField` name.                                                                                                                                                                  |
| `NamespacedKeyValidationError`                                               | — (`NamespacedKeyField`)                                         | **Delta.** A bespoke error class would compete with the family's single `Problem` type. The field identity survives as an enum.                                                                                                                                                                                                                                     |
| `sleep(seconds: number)`                                                     | `sleep(Duration)`                                                | **Delta (idiom).** Dart has a first-class `Duration`; a bare seconds `double` would be less safe. bun rejects with `RangeError`; dart returns `Err`.                                                                                                                                                                                                                |
| `noop`                                                                       | —                                                                | **Delta.** `() {}` is the idiomatic Dart no-op; a named wrapper adds nothing (`utilities` standard: prefer native over custom helpers).                                                                                                                                                                                                                             |
| `isRecord`                                                                   | `isJsonObject`                                                   | Renamed for the Dart reading: "record" is a distinct Dart language feature, so the bun name would actively mislead.                                                                                                                                                                                                                                                 |
| `stableConfig`                                                               | `stableConfig`, `stableConfigObject`                             | bun throws `TypeError` on a cycle; dart returns `record_unprojectable`. The `…Object` variant preserves `JsonObject` for merged configs.                                                                                                                                                                                                                            |
| `fuzzyIncludes`                                                              | `fuzzyIncludes`                                                  | Same.                                                                                                                                                                                                                                                                                                                                                               |
| `unique`                                                                     | —                                                                | **Delta.** Dart's `LinkedHashSet` already preserves insertion order, so `iterable.toSet().toList()` IS the first-occurrence filter. A helper would only re-export the SDK.                                                                                                                                                                                          |
| `sha256`                                                                     | —                                                                | **Delta.** `package:crypto` is the Dart-team-maintained, ecosystem-canonical answer and consumers should depend on it directly; a one-line wrapper would add a runtime dependency to a pure package for no gain.                                                                                                                                                    |
| `mapWithConcurrency`                                                         | `mapWithConcurrency`                                             | Kept, because Dart genuinely lacks it (`Future.wait` is unbounded). Signature differs: the dart mapper returns `Future<Result<R>>` and the first failure short-circuits by lowest index, rather than propagating a rejection.                                                                                                                                       |
| `safeJoin`, `ensureDirectory`, `readUtf8File`, `writeUtf8File`, `fileExists` | —                                                                | **Delta.** These are real-filesystem helpers over `node:fs`/`node:path`. Shipping dart equivalents would pull `dart:io` and `package:path` into `lib/`, which would end this package's web and Flutter support and cost pana's platform score. Path policy belongs to a `Vfs` implementation (`checkVfsPath` already ships in `diene_interfaces` for implementers). |
| `readVfsTextFile`, `writeVfsTextFile`                                        | `readVfsText`, `writeVfsText`                                    | Same shape — the portable half of bun's `fs`, over the published interface type. Dart additionally ships `readOptionalVfsText` and `loadConfigLayers`.                                                                                                                                                                                                              |
| `parseWireDate`/`formatWireDate` etc. (free functions over `Temporal`)       | `WireDate`/`WireTime`/`IsoDuration`/`IanaTimezone` + `WireCodec` | **Delta (idiom).** Dart has no `Temporal`, so validated value types carry the invariants a `Temporal.PlainDate` carries in bun. `WireTimeZone`'s branded string becomes the `IanaTimezone` value type. Dart additionally ships `normalizeRfc3339ToUtc` as an explicit ingress, where bun's `parseWireDateTime` accepts offsets directly.                            |
| —                                                                            | `c0TemporalContract`                                             | **Dart addition.** The family's shared temporal contract has no bun counterpart, because bun's C0 temporal cases live in its own fixture set.                                                                                                                                                                                                                       |

Cross-cutting delta: **dart has no `diene_frontend_utils` sibling**, so the
UX-pattern hooks the bun family splits out are not part of this package's parity
scope; the family goal assigns those to `auth-engine`/`api-engine`.

## TestHelper: NO

The family goal records a NO verdict for this lib, and `scripts/validate/dart-package.sh`
enforces it. Every member here is a pure function or a pass-through over an
injected seam: there is nothing to fake (`diene_interfaces` already ships
`InMemoryVfs`) and no assertion a consumer would repeat. The meta tier is a
successful no-op and uploads no `meta` codecov flag.

The shipped `diene-core-utils-usage` skill carries the meta convention and
explains exactly how to create a TestHelper for this lib should that ever change.

## Proof

| Gate                                | Command                                   |
| ----------------------------------- | ----------------------------------------- |
| unit + conformance, 100% ledger     | `./scripts/ci/test.sh unit coverage`      |
| meta no-op                          | `./scripts/ci/test.sh meta`               |
| analyze                             | `./scripts/ci/analyze.sh`                 |
| deadcode, two passes, no exclusions | `./scripts/local/deadcode.sh`             |
| package identity, seam, C0, IANA    | `./scripts/validate/dart-package.sh`      |
| frozen C0 release + projection      | `./scripts/validate/c0-release.sh`        |
| IANA provenance                     | `./scripts/validate/iana-source.sh`       |
| pub.dev score                       | `dart run pana --exit-code-threshold 0 .` |

C0 conformance is split by source, because release `c0-fixtures-r2` declares no
temporal domain:

- **§3 config** — `test/conformance/c0_config_test.dart`, driven from
  `test/fixtures/c0/config.json`, which `tool/gen_c0_projection.dart` projects
  from the frozen `contracts/c0/cases/config.json`. Editing an assertion cannot
  diverge it from the release; the projection check reddens.
- **§1 temporal** — `test/conformance/c0_temporal_test.dart`, driven from
  `c0TemporalContract` and authenticated by its own `contentSha256`.
- **IANA provenance** — `test/conformance/iana_source_test.dart`, which
  regenerates the allowlist from the vendored release and compares.
