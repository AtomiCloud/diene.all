---
name: diene-result-usage
description: Use @atomicloud/diene.result for async Railway Oriented Programming, SSR-safe Result/Option wire values, and framework-free variant assertions.
---

# Diene Result usage

Use this skill when composing fallible TypeScript work with
`@atomicloud/diene.result` or asserting its variants in tests.

Read the authoritative [Result and Option standard](https://github.com/AtomiCloud/diene.bun-result/blob/main/docs/standards/result/index.md).
Import only the package root or `/test-helper`; never copy the implementation or
reach into `src/` or `dist/`.

- Prefer `map`/`mapErr`/`andThen`/`match`; reserve `unwrap*` for proven boundaries.
- Await predicates, extraction, matching, and serialization: this API is async-native.
- Send only `serial()` tuples across SSR/process boundaries and rebuild with
  `Res.fromSerial` or `Opt.fromSerial`.
- In tests, await `expectOk`, `expectErr`, `expectSome`, or `expectNone` from
  `@atomicloud/diene.result/test-helper`.

Use `assets/consumer.ts`, `assets/consumer.cjs`, and `assets/test-helper.md` as
copyable package-boundary examples.
