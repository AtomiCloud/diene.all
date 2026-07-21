---
name: diene-result-usage
description: Use diene_result Result, Option, C0 wire codecs, and dependency-light consumer assertions in Dart.
---

# Diene Result usage

Import `package:diene_result/diene_result.dart`; do not reach into `lib/src` or
copy the monads into an application. Prefer `match`, `map`, `mapErr`, and
`andThen` for ordinary control flow, reserving `unwrap` for an invariant already
proved at the call site.

Use `serial()`/`fromSerial()` only at a wire boundary. The format and deliberate
Bun-family deltas are documented in `doc/result.md`.

In consumer tests, import `package:diene_result/test_helper.dart` and use
`expectOk`, `expectErr`, `expectSome`, or `expectNone`. They throw plain
`TestHelperFailure` values and add no test framework to the production graph.
