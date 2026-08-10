# Result and Option

`@atomicloud/diene.result` is the zero-runtime-dependency Result/Option stack for
the TypeScript family. It turns expected failure into values and supports
[Railway Oriented Programming](https://fsharpforfunandprofit.com/rop/) without
making exceptions part of ordinary control flow.

## Public surface

- `Result<T, E>` is the interface; `KResult<T, E>` is its concrete implementation.
- `Ok(value)` and `Err(error)` create Results. `Res.fromSerial`,
  `Res.fromAsync`, `Res.async`, and `Res.all` compose them.
- `Option<T>` is the interface; `KOption<T>` is its concrete implementation.
- `Some(value)` and `None()` create Options. `Opt.fromNative`,
  `Opt.fromSerial`, `Opt.fromAsync`, `Opt.async`, and `Opt.all` compose them.
- `UnwrapError` is thrown only when explicit `unwrap`/`unwrapErr` use asks for
  the wrong variant.
- `ResultSerial<T, E>` and `OptionSerial<T>` are JSON-safe discriminated tuples.

All predicates, extraction, transforms, matching, projections, and wire methods
are async-native because constructors accept promised values.

## Compose along the railway

```ts
import { Err, Ok, type Result } from '@atomicloud/diene.result';

type ParseError = { input: string };

const parsePositive = (input: string): Result<number, ParseError> => {
  const value = Number(input);
  return Number.isFinite(value) && value > 0 ? Ok(value) : Err({ input });
};

const label = await parsePositive('21')
  .map(value => value * 2)
  .match({ ok: value => `value:${value}`, err: error => `invalid:${error.input}` });
```

Prefer `map` for successful values, `mapErr` for the error channel, `andThen`
for another fallible step, and `match` at the boundary. Use `run` for an
uncaught side effect and `exec` when a thrown side-effect failure should poison
the chain as `Err<Error>`.

Do not unwrap speculatively. `unwrap` and `unwrapErr` are for boundaries where
the variant has already been proven, or for concise test code.

## Option projection and conversion

`result.ok()` and `result.err()` project one Result channel into Option.
`option.asOk(error)`, `option.asErr(okValue)`, and `option.asResult(arms)` move
back into Result. `Opt.fromNative(null | undefined)` yields `None`; other
values, including `0`, `false`, and empty strings, yield `Some`.

## SSR and wire boundaries

Classes are not the wire format. Call `serial()` before passing a value through
JSON, SSR hydration, a worker boundary, or another process:

```ts
import { Ok, Res, type ResultSerial } from '@atomicloud/diene.result';

const wire: ResultSerial<number, string> = await Ok<number, string>(42).serial();
const hydrated = Res.fromSerial<number, string>(JSON.parse(JSON.stringify(wire)));
```

Result uses `['ok', value] | ['err', error]`; Option uses
`['some', value] | ['none', null]`. Rebuild only from trusted/validated payload
types at an application boundary; the package preserves the payload and tag.

## TestHelper

Import TestHelper only in tests:

```ts
import { Ok } from '@atomicloud/diene.result';
import { expectOk } from '@atomicloud/diene.result/test-helper';

const value = await expectOk(Ok<number, string>(2));
```

`expectOk`, `expectErr`, and `expectSome` return the unwrapped payload for
continued assertions; `expectNone` returns `void`. A mismatch throws
`TestHelperError` with expected variant, actual variant, and a formatted payload
diff. The helper has no test-framework dependency.

## Family-wide meta-testing convention

TestHelper code belongs to the `meta` tier, not unit coverage. Every helper must
be tested as an asserter: one known-good value passes, one known-bad value throws,
and the mismatch message/payload diff is asserted. Run `pls test:meta` or
`pls test:meta:coverage`; the meta ledger covers only `src/test-helper/**` at
100%. Product unit coverage covers only `src/lib/**` at 100%.

## Package boundaries

Use only `@atomicloud/diene.result` and
`@atomicloud/diene.result/test-helper`. Do not import from `dist/`, copy the
monad files into a consumer, or add a runtime dependency to simulate methods
already provided here.
