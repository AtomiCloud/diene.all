---
name: diene-go-errors-problems-usage
description: Use the diene Go errors-problems library (RFC 9457 Problem envelopes, the single-source type-URI builder, the typed registry/catalog, problem-typed errors, and the TestHelper assertions).
---

# Diene Go errors-problems usage

`github.com/AtomiCloud/diene.go-errors-problems/lib/problem` is the Go family's
result slot: **no monad — idiomatic `(T, error)`** where the error carries an
RFC 9457 `Problem` (C0 §2/§14). Read the compiling examples in
`lib/problem/example_test.go` and the package docs on pkg.go.dev.

## Do

- Build every `type` URI through the ONE builder `problem.TypeURI(portal,
version, id)` (or `Registry.TypeURIFor`). The `{version}` segment is part of
  the identity (D8) — a version bump mints a NEW type. Never hand-format the
  template.
- Return failures as `*problem.Error` (via `NewError` /
  `WrapError` for `%w` chains). Recover with
  `var pe *problem.Error; errors.As(err, &pe)`.
- Register the portable baseline with `problem.RegisterGenerics(registry)`;
  export the per-service catalog with `Catalog.AddType(...)` +
  `ToCRDContent()` (the C0 §14 `problems[]` rows).
- Fold any value into a `Problem` with `problem.FromObject(value, opts)` — it
  never panics; unknown ids become an uncatalogued 5xx (C0 §14 catalog-loop).
- Wrap unexpected client-side errors with `problem.LocalError.Wrap` (message +
  stack land in `data`).

## Don't

- Don't build type URIs in more than one place, drop `{version}`, or invent a
  second `Problem` shape — the wire keys are
  `type,title,status,detail?,instance?,recoverable,data`.
- Don't add `export_test.go` or white-box shims; every test is an external
  `_test` package.

## TestHelper

Import `github.com/AtomiCloud/diene.go-errors-problems/testhelper` in tests to
stop repeating `errors.As` + field-by-field Problem checks:

- `testhelper.AssertError(t, err, testhelper.ExpectID("entity-not-found"),
testhelper.ExpectStatus(404))` — recover and match a Problem from a
  `(T, error)` result.
- `testhelper.CheckProblem(p, opts...)` returns the first mismatch (framework-
  free); `AssertProblem` fails the test.
- `testhelper.SampleProblem()` / `SampleErrorPortal()` mint valid fixtures whose
  type URIs come from the single-source builder.

New helper behavior needs black-box meta tests (`tests/meta/...`) and 100% meta
coverage. Before changing an exported API run `./scripts/ci/pkg-validate.sh all`;
keep v1 changes backward compatible (an intentional break needs a `/v2` module).
