# Dart core utilities

`diene_core_utils` is the pure value layer for Diene Dart consumers. Import the
single barrel:

```dart
import 'package:diene_core_utils/diene_core_utils.dart';
```

## Keys and timing

`slugify` applies Unicode NFKD normalization, removes combining marks, lowercases,
and collapses non-ASCII-alphanumeric runs into one kebab separator.

`namespacedKey(namespace, key)` returns a sealed `NamespacedKeyResult`, never
throws, and produces `namespace:key` only when both normalized components are
non-empty. During family stacking the conductor replaces this local result-shaped
bridge with the final `diene_result.Result` type; the validation fields and value
semantics remain unchanged.

`sleep(Duration)` delegates to Dart scheduling and rejects negative durations.

## Merge and environment coercion

`deepMerge` is immutable. Maps merge recursively; lists, nulls, and scalars replace.
Keys match case-insensitively across snake, kebab, camel, and Pascal forms.

`environmentToNestedMap` accepts an explicit prefix and uses `__` for nesting.
Numeric components are contiguous zero-based list indexes. Blank variables are
unset. Booleans, safe integers, and decimal/scientific forms are coerced; integers
outside ±(2^53−1) stay strings. JSON-in-env and comma-list encodings are never
decoded.

## C0 wire forms

`WireCodec` enforces the family contract:

| Domain value   | Wire form                      |
| -------------- | ------------------------------ |
| `WireDate`     | `YYYY-MM-DD`                   |
| `WireTime`     | `HH:mm:ss`                     |
| UTC `DateTime` | RFC 3339 instant ending in `Z` |
| `IsoDuration`  | ISO 8601 duration              |
| `IanaTimezone` | IANA area/location identifier  |

Display/locale formats never cross the wire. Offset or abbreviated timezone values
are rejected. Instants are formatted in UTC even when the input has a local offset.

## TestHelper and meta tier

Verdict: **NO**. These are pure deterministic values/functions. There is no port,
I/O fake, nondeterministic seam, complex construction, or repeated consumer
assertion that stock equality cannot express. `pls test:meta` therefore succeeds as
an explicit no-op and CI uploads no empty `meta` coverage flag.

If future evidence changes that verdict, make the change in this exact shape:

1. Add dependency-light `lib/test_helper.dart` inside this package. It may contain
   fakes, builders, or plain-throw assertions only; never import `test`, `matcher`,
   or a mocking framework from runtime code.
2. Add `test/meta/` tests proving every assertion passes a known-good case and
   fails a known-bad case, every fake shares one behavioral suite with the real
   implementation, and every fixture/builder preserves its invariants.
3. Activate `pls test:meta` and `pls test:meta:coverage`; measure only
   `test_helper.dart` at the family high threshold and exclude it from unit coverage.
4. Upload a `meta` codecov flag only when that helper exists, and teach the existing
   `diene-core-utils-usage` skill how consumers import it.

Re-open only when an actual consumer seam must be faked or the same nontrivial
assertion is repeated across consumer suites—not merely to mirror another package.

## Bun-family parity deltas

- Dart keeps deep merge and env-path coercion in core-utils because the Dart family
  row assigns them here for config consumption; the current Bun goal moved those
  helpers to its config package.
- Dart uses `Duration`/`Future<void>` rather than seconds for `sleep`.
- Dart does not port Bun filesystem, hashing, fuzzy, concurrency-map, record, or
  unique helpers in this node; the assigned Dart row is limited to the evidenced
  slug/key/timing/config-value/wire surface and S33 owns filesystem seams.
- Dart wire types are dependency-free value wrappers plus `DateTime`; no Temporal
  polyfill or JSON converter framework is required.
- Dart ships no frontend-only class-name helper and no OTel surface.
