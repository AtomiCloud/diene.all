---
name: diene-result-usage
description: Use the AtomiCloud Result/Option monad package from ESM, CommonJS, or TypeScript, including its /test-helper subpath.
---

# Diene Result usage

Import the public package surface; do not copy its implementation or reach into
`dist/` or `src/`. Use the ESM example in `assets/consumer.ts` or the CommonJS
example in `assets/consumer.cjs` as the smallest integration check.

`@atomicloud/diene.result` exposes `Result<T, E>` and `Option<T>` as tagged
discriminated unions with same-named const companions carrying the
constructors:

```ts
import { Option, Result } from '@atomicloud/diene.result';

const doubled = Result.ok<number, string>(21)
  .map(value => value * 2)
  .unwrapOr(0);

const present = Option.fromNullable(process.env.HOME).isSome;
```

- `Result.ok(v)` / `Result.err(e)`, `Option.some(v)` / `Option.none()` /
  `Option.fromNullable(v)` build values.
- `map`, `mapErr`, `andThen`, `match`, `run`, and the poison-the-chain `exec`
  transform them; `unwrap`/`unwrapErr` throw `UnwrapError` on the wrong variant.
- `serial()` / `Result.fromSerial(...)` round-trip the JSON-safe tagged-object
  wire `{ kind, value | error }`.
- Async composition uses the free functions `mapAsync`, `mapErrAsync`,
  `andThenAsync`, `matchAsync`, `unwrapAsync`, and `unwrapErrAsync` over a
  `Promise<Result<T, E>>`.

The error channel is generic (`E`), so pick any error type — this package does
not depend on a problems library. For consuming the assert-the-asserter
helpers, follow `assets/test-helper.md`.
