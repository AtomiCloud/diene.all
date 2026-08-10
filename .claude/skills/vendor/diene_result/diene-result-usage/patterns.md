# diene_result patterns

## Keep failures explicit

Use `map`, `mapErr`, `andThen`, and `match` for routine control flow. Reserve
`unwrap` and `unwrapErr` for invariants already proved at the call site. The
ordinary combinators deliberately let callback exceptions propagate; `exec`
is the explicit boundary for converting a thrown object and stack trace into
the canonical `Problem` from `diene_problems`.

## Encode only at boundaries

Keep `Result<T>` and `Option<T>` inside application code. Use `serial()` and
`fromSerial()` only at a JSON boundary, supplying a decoder for the success or
some payload. The C0 wire forms are exactly `['ok', value]`,
`['err', problemJson]`, `['some', value]`, and `['none', null]`.

## The TestHelper pattern

`lib/test_helper.dart` imports the public Result barrel and `diene_problems`,
but no test framework. Its assertions return useful payloads and throw plain
`TestHelperFailure` values on a variant mismatch, so consumers can use them
under `package:test`, Flutter test, or another runner.

Keep the helper honest with assert-the-asserter meta tests: every assertion
must accept a known-good variant and reject a known-bad one. Meta coverage is a
separate 100% ledger scoped only to `lib/test_helper.dart`; the unit ledger is
scoped to `lib/src/**`.
