# Result and Option

`diene_result` ships sealed `Result<T>` and `Option<T>` values, synchronous
combinators, async extensions over `Future<Result<T>>`, and the C0 wire codec.
It depends on `diene_problems`, the Dart-family owner of the RFC 9457 failure
identity.

## Result

Construct values with `Result.ok` and `Result.err`. Transform only success with
`map`, transform only failure with `mapErr`, chain fallible work with `andThen`,
and consume both variants with `match`.

Explicit `unwrap` misuse throws `UnwrapError`; routine control flow should use
`match`, projections, or the fallback methods. `run` does not capture callback
exceptions. `exec` captures only when the caller supplies the explicit
exception-to-`Problem` mapper.

The Dart C0 contract preserves the Flutter seed's one-parameter `Result<T>`.
Its error channel imports the canonical RFC 9457 `Problem` envelope from
`package:diene_problems/diene_problems.dart`. Result neither defines nor
re-exports `Problem`; consumers that construct or name failures import the
Problems package directly.

## Option

Use `Option.some`, `Option.none`, or `Option.fromNullable`. The `map`,
`andThen`, `match`, and unwrap-family methods mirror Result. `okOr` turns Some
into Ok and None into Err; `errOr` on `Option<Problem>` performs the inverse.

## C0 wire form

The JSON representation is a two-item tagged array:

```text
Result: ["ok", value] | ["err", problemJson]
Option: ["some", value] | ["none", null]
```

`Result.fromSerial` and `Option.fromSerial` require an explicit success-value
decoder. They reject unknown tags, incorrect arity, a non-object Problem, and a
non-null None payload. `test/fixtures/c0/result_wire.json` is a locally derived
regression input, explicitly not an authoritative source-owned C0 fixture. No
source-owned Result/Option fixture exists in the available shared C0 material,
so authoritative fixture conformance remains an integration hold.

## TestHelper and meta testing

Consumer tests may import `package:diene_result/test_helper.dart` and use
`expectOk`, `expectErr`, `expectSome`, and `expectNone`. Each assertion returns
the unwrapped payload when useful and throws `TestHelperFailure` with the actual
variant and payload on mismatch. The helper imports no test framework; its
`Problem` return type is the canonical `diene_problems` type.

The meta suite is assert-the-asserter coverage: each helper is shown passing on
a known-good value and failing on a known-bad value. Its 100% coverage ledger
contains only `lib/test_helper.dart`; TestHelper code is excluded from the unit
ledger.

## Deliberate deltas from lib/bun/result

- Dart uses a sealed synchronous class hierarchy; Bun uses an async-native
  promise-backed implementation. Dart async composition is an extension on
  `Future<Result<T>>`.
- C0 fixes Dart to the seed-compatible `Result<T>` with a `Problem` error
  channel. Bun exposes a generic `Result<T, E>`.
- The wire arrays are identical, but no SSR-specific API ships in Dart.
- Dart's `exec` requires an explicit exception-to-Problem mapper; ordinary
  `map`, `mapErr`, `andThen`, and `run` let exceptions propagate.
- Bun's heterogeneous `all` and error-collecting type machinery has no honest
  single-Problem Dart equivalent and is intentionally absent.
- Dart uses `Result.ok`/`Result.err`, `Some`/`None`, and lower-camel method names
  instead of TypeScript factory-function vocabulary.
