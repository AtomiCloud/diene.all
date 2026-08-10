# diene_core_utils patterns

Worked examples, the failure vocabulary, and the meta-tier convention.

## Composing failures instead of catching them

`Result` short-circuits, so a chain reads top to bottom with one failure handler.

```dart
final Result<String> cacheKey = namespacedKey(tenant, resource)
    .andThen((String key) => IanaTimezone.parse(zone).map((IanaTimezone z) => '$key@$z'));

final String rendered = cacheKey.match(
  ok: (String key) => key,
  err: (Problem problem) => 'unusable: ${problem.detail}',
);
```

Never do this:

```dart
// WRONG: nothing here throws, so the catch is dead code that hides the Problem.
try {
  final key = namespacedKey(tenant, resource).unwrap();
} catch (_) { /* ... */ }
```

## The configuration ladder

C0 §3 precedence is `base → flavor/landscape overlay → --dart-define`, and that
is literally the argument order to `deepMergeAll`.

```dart
final JsonObject config = deepMergeAll(<JsonObject>[
  baseYaml,                                                     // lowest
  landscapeYaml,
  environmentToNestedMap(defines, prefix: 'ACME_').unwrap(),     // highest
]);
```

Key matching is case- and separator-insensitive, and **the first layer's spelling
wins as the output key**:

```dart
deepMerge(
  <String, Object?>{'display-name': 'base'},
  <String, Object?>{'DisplayName': 'overlay'},
);
// {display-name: overlay}  — one key, the base's spelling, the overlay's value
```

The prefix is matched case-insensitively too, so a host that folds its
environment to lower case still contributes:

```dart
environmentToNestedMap(<String, String>{'acme_app__name': 'x'}, prefix: 'ACME_');
// Ok({app: {name: x}})
```

Lists come only from indexed keys:

```dart
// RIGHT
{'ACME_TAGS__0': 'a', 'ACME_TAGS__1': 'b'}   // -> {tags: [a, b]}
// WRONG — carried through as the string it is, never decoded
{'ACME_TAGS': '["a","b"]'}
{'ACME_TAGS': 'a,b'}
```

Indexes must start at zero and be dense; a sparse list is a `Problem`, not a
silently compacted list.

## Deterministic projection

Use `stableConfig` before hashing, diffing, or caching a configuration — two
structurally equal configs then produce byte-identical JSON.

```dart
final String digest = sha256
    .convert(utf8.encode(jsonEncode(stableConfigObject(config).unwrap())))
    .toString();
```

Circular input is reported (`record_unprojectable`) with the path where the cycle
was found, rather than recursing forever.

## Instants: one canonical spelling

```dart
// Ingress: accept the wider grammar ONCE, at the boundary.
final Result<String> canonical = normalizeRfc3339ToUtc(payload['created_at'] as String);

// Everywhere after that, the strict parser is what you use.
final Result<DateTime> at = parseRfc3339Utc(canonical.unwrap());
```

`parseRfc3339Utc('2026-07-26T01:02:03+00:00')` is an `Err` on purpose. Fixing one
spelling is what lets two services compare wire bytes instead of parsing to
compare; accepting equivalent spellings would reintroduce the drift the surface
exists to remove.

A zone-less timestamp (`2026-07-26T01:02:03`) is rejected by both members: it
means nothing without the writer's zone.

## Timezones are checked against a pinned release

`IanaTimezone.parse` and `isIanaTimeZone` test exact membership in a vendored,
digest-pinned IANA release (`ianaTimeZoneRelease`), never host tzdata. So:

- `EST`, `GMT`, `US/Eastern` are ACCEPTED — genuine IANA database entries.
- `PST` is REJECTED — an abbreviation with no IANA entry.
- `asia/singapore` is REJECTED — membership is case-sensitive.
- `+08:00` is REJECTED — an offset is not a zone; a zone carries DST rules.

## Injecting the filesystem seam

Take `Vfs` as a parameter so your code is testable without a host filesystem.

```dart
final class SettingsStore {
  const SettingsStore(this._vfs);
  final Vfs _vfs;

  Future<Result<JsonObject>> load() => loadConfigLayers(_vfs, <ConfigLayer>[
    ConfigLayer(path: '/etc/acme/base.yaml', parse: _yaml),
    ConfigLayer(path: '/etc/acme/$landscape.yaml', parse: _yaml, optional: true),
  ]);
}
```

```dart
// In a test — no host filesystem, no mocking framework.
import 'package:diene_interfaces/test_helper.dart';

final InMemoryVfs vfs = InMemoryVfs();
await writeVfsText(vfs, '/etc/acme/base.yaml', 'name: test');
final Result<JsonObject> loaded = await SettingsStore(vfs).load();
```

Mark a layer `optional` when its absence is legitimate. `readOptionalVfsText`
models absence as `Ok(null)`; every OTHER seam failure (permission, I/O,
not-a-file) still propagates, so a real misconfiguration is never mistaken for
"the file simply is not there".

## Bounded concurrency

```dart
final Result<List<Manifest>> manifests = await mapWithConcurrency(
  packages,
  4,
  (Package p) async => fetchManifest(p),   // must return Future<Result<Manifest>>
);
```

Guarantees worth relying on: results keep INPUT order; at most `bound` mappers are
ever in flight; the first failure stops new work being claimed; and the LOWEST
failing index is the one reported, so the outcome does not depend on which call
happened to finish first.

## The failure vocabulary

Every `Problem` from this package carries `data.util`, `data.code`, and
`data.operation`, and its `type` URI is minted by `problemTypeUri` — the single
C0 §2 builder — at version `v1`.

| `util`        | `code`           | Raised by                                                              |
| ------------- | ---------------- | ---------------------------------------------------------------------- |
| `slug`        | `invalid_input`  | `namespacedKey` when a part slugifies to empty (`data.field` names it) |
| `coercion`    | `invalid_input`  | an empty path component, mixed indexed/named children, a sparse list   |
| `coercion`    | `conflict`       | two keys normalising onto one path, or a scalar path used as a parent  |
| `record`      | `unprojectable`  | `stableConfig` on cyclic input (`data.path`)                           |
| `wire`        | `invalid_format` | any temporal parse rejection (`data.expected`, `data.value`)           |
| `timing`      | `invalid_input`  | `sleep` with a negative duration                                       |
| `concurrency` | `invalid_input`  | `mapWithConcurrency` with a bound below 1                              |
| `vfs`         | `invalid_input`  | `loadConfigLayers` when no layer was present at all                    |

`recoverable` is always `false`: every failure this package reports is a
deterministic function of its input, so retrying the identical call cannot change
the outcome. A genuinely retryable failure can only come from the `Vfs` seam, and
these helpers pass that envelope through unchanged so its `recoverable: true`
survives.

## Driving your own C0 temporal conformance

Do not restate temporal cases. Import the shared contract and iterate it, so your
package and every sibling move together when the contract version changes.

```dart
import 'package:diene_core_utils/c0_temporal.dart';

for (final String valid in c0TemporalContract.dates.valid) {
  expect(myDateSurface.accepts(valid), isTrue, reason: valid);
}
for (final String invalid in c0TemporalContract.dates.invalid) {
  expect(myDateSurface.accepts(invalid), isFalse, reason: invalid);
}
for (final C0InstantVector vector in c0TemporalContract.instants) {
  expect(myNormaliser(vector.input), vector.canonicalUtc);
}
```

`c0TemporalContract.provenance` pins the C0 source document, the IANA release and
archive digest, and a `contentSha256` over the vectors themselves — so a silent
vector edit reddens the owning package's conformance suite rather than quietly
changing what every consumer proves.

## The meta tier and this package's TestHelper

**This package ships no `test_helper.dart`, and that is a recorded decision, not an
omission.** Its members are pure functions or pass-throughs over an injected seam:
there is nothing a consumer must fake (`diene_interfaces` already ships
`InMemoryVfs`) and no assertion a consumer would repeat in every test. Shipping a
helper would add public surface that helps nobody.

The family's meta machinery is registered in the Dart lib base and activates only
where a TestHelper exists. Here, `./scripts/ci/test.sh meta` is a successful
no-op and NO `meta` codecov flag is uploaded. `scripts/validate/dart-package.sh`
asserts the absence, so adding a helper is a deliberate change that must update the
goal row and that gate together.

**If that ever becomes justified**, the family convention is:

1. Add `lib/test_helper.dart` as a sub-library of THIS package — not a separate
   package. It must stay DEPENDENCY-LIGHT: fakes, builders, and plain-throw
   assertions only, with **no** `test`, `matcher`, `mockito`, or `mocktail` import,
   so it adds nothing to a consumer's production dependency graph.
2. Throw a package-specific `Exception` subtype (the siblings' `TestHelperFailure`
   and `SeamAssertionFailure` are the model) rather than depending on `matcher`, so
   the helper works with `package:test`, `flutter_test`, or any other runner.
3. Add `test/meta/` covering the helper itself. The meta tier's subject is the
   helper's own code, and its content is assert-the-asserter: every assertion
   helper shown to FAIL on a known-bad case and to pass on a known-good one, plus
   fixture and builder invariants.
4. The base machinery then activates on its own — `pls test:meta` runs, the
   TestHelper-only coverage ledger applies at the single high threshold, and the
   `meta` codecov flag uploads. The unit ledger continues to exclude
   `lib/test_helper.dart`.
5. Update the `core-utils` TestHelper verdict in `goals/lib/dart-family.md` and the
   assertion in `scripts/validate/dart-package.sh` in the SAME change, so the goal
   and the gate never disagree.

The escape hatch — a separate `diene_core_utils_test_helper` package — exists only
for a helper that TRULY needs framework dependencies. It is the exception, not the
default.
