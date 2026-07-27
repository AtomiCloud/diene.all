# Result and Option

`Result<T, E>` is a guarded `readonly struct` with Success and Failure
variants. `Option<T>` is the corresponding Some/None value. Both reject their
default zero state with `InvalidResultException`; wrong-variant `Get` calls
throw `UnwrapException` and preserve the other channel's value for diagnosis.

Use `Map` for successful values, `MapFailure` for errors, and `Then` for
Result-returning continuations. Result-returning callbacks never capture
exceptions. Raw-function overloads accept an `ExceptionFilter` and an error
mapper; matching exceptions become Failure and unmatched exceptions rethrow.

The in-memory structs are not wire models. `ResultSerial<T, E>` and
`OptionSerial<T>` encode the C0 v1 tuples:

- `["ok", value]`
- `["err", error]`
- `["some", value]`
- `["none", null]`

The source-owned regression fixture is
`fixtures/c0/monad-v1.json`. It is versioned and exercised in both the
unit and host-safe integration tiers. Its explicit `local-regression-only`
status does not claim a shared cross-language fixture or external C0 proof.
