---
name: diene-result-usage
description: Use diene_result Result, Option, C0 wire codecs, canonical diene_problems failures, and dependency-light consumer assertions in Dart.
---

# Diene Result usage

Import `package:diene_result/diene_result.dart` for the monads and
`package:diene_problems/diene_problems.dart` whenever code constructs or names
the error channel. `diene_problems` owns the sole public `Problem` identity;
Result imports it and deliberately does not re-export it. Do not reach into
`lib/src` or copy either type into an application. Prefer `match`, `map`,
`mapErr`, and `andThen` for ordinary control flow, reserving `unwrap` for an
invariant already proved at the call site.

Use `serial()`/`fromSerial()` only at a wire boundary. The format and deliberate
Bun-family deltas are documented in `doc/result.md`.

In consumer tests, import `package:diene_result/test_helper.dart` and use
`expectOk`, `expectErr`, `expectSome`, or `expectNone`. They throw plain
`TestHelperFailure` values and add no test framework to the production graph.
Import `diene_problems` directly when naming the `Problem` returned by
`expectErr`.
