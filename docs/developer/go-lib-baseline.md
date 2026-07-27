# Go library baseline

This template publishes the module
`github.com/AtomiCloud/diene.go-otel`. A materialized child changes the final
`go-lib` token to its library name in `.config/go-lib.yaml`, `go.mod`, mirror
URLs, badges, documentation, and its usage-skill namespace. The mirror remains
a single-module repository unless a concrete library proves otherwise.

## Package and API shape

Keep public packages small and cohesive, and carry zero private (unexported)
logic (B9). Private fields are fine; private logic is not — every unexported
helper is a hidden dependency, so it graduates to either an injected service or
a cohesive `internal/<name>` package whose exported surface is black-box tested
like any other package and whose nondeterminism is reached through injected
determinism seams. `internal/` keeps that surface unimportable outside the
module without ever exposing logic solely for tests. Every exported symbol has a
doc comment, and `Example*` functions are executable consumer documentation.
All tests use external `_test` packages, and `export_test.go` is forbidden;
`scripts/validate/go-black-box-tests.sh` (pre-commit hook `a-go-black-box`)
enforces both by rejecting any `export_test.go` or non-`_test` test package.

The inherited `note` package and Redis adapter are replaced wholesale by three
OpenTelemetry surfaces:

- `lib/otel` owns the pure C0 block, JSON Schema, validation, environment
  precedence, resource mapping, problem faults, and language-local trace seam.
- `adapters/otelsdk` owns real OpenTelemetry SDK wiring and lifecycle. Stable
  public signatures contain no pre-1.0 logs SDK types; those remain confined to
  `adapters/otelsdk/internal/logbridge`.
- `testhelper` owns the three validating in-memory emission doubles, exact
  assertions, and canonical fixtures.

The module has no `main` or `cmd` package. `go build ./...`, `go vet ./...`,
golangci-lint, govulncheck, strict deadcode, examples, and `gorelease` protect
the resulting library shape.

## Telemetry contract

Start from `otel.DefaultConfig()`: all three signals are enabled, both exporter
types are off, export timeout is `PT10S`, metrics interval is `PT60S`, and the
sampler is `parentbased_traceidratio` at `1.0`. Landscape overlays enable OTLP
at an HTTP(S) endpoint with explicit port 4318 and fixed protocol
`http/protobuf`. Compose `otel.JSONSchema()` under `otel.SchemaKey()`; the
configuration library remains the sole merger and strict decoder.

Build one `otelsdk.Runtime` from a validated `otel.AppIdentity`. The runtime
derives four semantic-convention and five raw `atomi.*` resource attributes.
`OTEL_SDK_DISABLED` always wins, while set `OTEL_*` values defer to the upstream
SDK instead of being overwritten by explicit options. Global provider
registration defaults to false and is an application boot-time opt-in.

Logs, metrics, and traces validate even when provider-free. An injected seam
owns its signal, so no exporter or provider is constructed for it. OTLP logs
are real; the pre-1.0 logs dependency is hidden behind an opaque stable handle.

## Test pyramid and TestHelper

Unit coverage targets domain packages at 100%. Integration coverage targets
user-designed adapters against real dependencies. The conditional meta tier
targets `<module>/testhelper` only: when that package exists, `pls test:meta`
and `pls test:meta:coverage` run its black-box contract, failure, assertion, and
fixture tests; when it does not exist, they succeed without uploading an empty
Codecov flag. TestHelper code is excluded from the unit ledger.

Choose a TestHelper only when consumers would otherwise repeat fakes,
assertions, nondeterminism seams, or complex construction. Ship it as the
`testhelper` subpackage and document its use in the module's single usage skill.
For a NO verdict, keep the same skill but explain how to add a future helper
without privileged test exports.

This module's verdict is YES. Consumer tests inject
`NewInMemoryLoggerSink`, `NewInMemoryMetricsCollector`, and
`NewInMemoryTraceEmitter`; no test tier starts a collector, container, or
network telemetry service. RB-19 requires Go trace tests to emit through the
language-local trace double and assert with `AssertTraceRecords`. Meta tests
prove mock-versus-real validation parity for all three signals and prove every
`Assert*` helper against known-good and known-bad inputs.

## Compatibility and major versions

`gorelease` is the only API-compatibility tool. The template compares the
current public surface with a sealed local v1 baseline so compatibility is
host-provable before the first mirror tag. Each concrete library replaces that
fixture with its accepted v1 surface. Removing or renaming an export in v1 is
rejected. A deliberate major release uses a `/v2` module suffix; implementing
that migration is outside this v1 template.

## Release and publication

Semantic release computes the version and changelog, commits those generated
documents, and creates a `vX.Y.Z` Git tag. Go has no manifest version and no
registry push, so this branch deliberately has no bump script. The tag is the
release, and the public Go proxy serves the mirror repository.

The CD path refuses missing, malformed, prefixed, prerelease, or build-metadata
tags before it reaches the proxy. It then builds the module and resolves the
exact tag into a clean consumer through `https://proxy.golang.org`. Mirror
creation, the first real tag, and that external round trip require the deferred
publication authority; local guards and workflow wiring remain fully testable.

## Template-maintenance boundary

Children may replace sample packages and tests, tune coverage only when their
real surface justifies it, update identity sync points, refresh the API baseline
at an accepted release boundary, and revise badges. Preserve strict black-box
testing, conditional meta mechanics, documentation/examples, compatibility
validation, tag refusal, and single-module publication unless a reviewed design
explicitly changes them.
