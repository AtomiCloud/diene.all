---
name: diene-go-config-usage
description: Use the diene Go config library (Viper-seeded base/overlay/env layering, JSON Schema draft 2020-12 composition and validation, problem-typed failures, typed-slice decode, and the TestHelper fakes and assertions).
---

# Diene Go config usage

`github.com/AtomiCloud/diene.go-config/lib/config` loads, merges, validates, and
decodes Diene service configuration. It layers a base YAML of full defaults, a
sparse per-landscape overlay, and the process environment **last**, validates the
final merged tree once against a composed JSON Schema, and returns failures as
problem-typed `(T, error)` values. Read the compiling examples in
`lib/config/example_test.go` and the package docs on pkg.go.dev.

## Do

- Build a loader with `config.NewLoader(...)` and always set the required
  `config.WithEnvPrefix("ATOMI_")` — there is no default prefix; `ATOMI_` is only
  an example. Supply the base via `config.WithBaseSource` or `config.WithBaseDir`,
  and the required schema via `config.WithSchema`. `Loader.Load` fails fast when
  the prefix, base, or schema is missing — startup validation is never skipped.
- Layer precedence is base < overlay < environment. Resolve the landscape with
  `config.WithLandscape` or let it come from the base `app.landscape`; the
  sentinel `config.BaseLandscape` ("base") applies no overlay.
- Express environment lists as **indexed keys** — `ATOMI_CACHE__REPLICAS__0`,
  `ATOMI_CACHE__REPLICAS__1` — never a JSON or comma-encoded string. Nesting uses
  `__`; blank values are unset; keys match across snake, kebab, camel, and Pascal.
- Compose the root schema from engine-owned blocks with
  `config.ComposeSchema(config.AppBlockSchema(), otel.Block(), ...)`. config owns
  only the service-tree `app` block; each engine exports its own `config.Block`.
  Generate a fragment from a Go type with `config.GenerateSchema` /
  `config.FragmentFromType`, and load the shipped artifact with
  `config.SchemaFromJSON`.
- Serve typed values with `cfg.Decode("cache.replicas", &replicas)` and read the
  identity block with `cfg.App()`.
- Recover a validation failure with `var pe *problem.Error; errors.As(err, &pe)`
  or `config.ValidationIssues(err)`; failures are the `validation-error` catalog
  member (HTTP 400, recoverable) carrying `{path, message}` field data.
- Give every committed config YAML a schema pointer on its **first line**
  (`# yaml-language-server: $schema=...`) and keep secret examples blank.

## Don't

- Don't define otel, auth-engine, api-engine, or standard-config block schemas
  here — config merges and validates them, it never owns them.
- Don't rely on Viper `AutomaticEnv`; the env layer is produced by
  `coreutils.EnvironmentToNestedMap` so lists and casing behave per the contract.
- Don't validate a single layer — validation runs once, on the final merged tree,
  and fails fast on an invalid result.
- Don't add `export_test.go` or white-box shims; every test is an external
  `_test` package.

## TestHelper

Import `github.com/AtomiCloud/diene.go-config/testhelper` in tests to drive the
real loader over in-memory fakes without touching the filesystem or environment:

- `testhelper.BaseSource(doc)`, `testhelper.OverlaySource(landscape, doc)`, and
  `testhelper.EnvSource(map[string]string{...})` are the fake layers.
- `testhelper.Schema()` composes the app block with a neutral demo block;
  `testhelper.InvalidSchemaBlock()` and `testhelper.InvalidOverlayDocument()`
  drive the fault and fail-fast paths.
- `testhelper.StubConfig(raw)` / `testhelper.StubApp(app)` are **unchecked**
  decode/accessor stubs — they wrap a map you assert is valid and do NOT
  validate. Use `testhelper.ValidRaw()` for a map proven to satisfy the schema,
  or run the real `config.Loader` when validity matters.
- `testhelper.RequireConfig(t, cfg, err)`, `RequireLoadError(t, cfg, err)`, and
  `RequireIssue(t, err, "app.version")` are framework-free assertions over the
  minimal `testhelper.TestingT` interface.

Before changing an exported API, run `./scripts/ci/pkg-validate.sh all`. Keep v1
changes backward compatible; an intentional breaking release needs a reviewed
`/v2` module-path migration.
