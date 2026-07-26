# Go library baseline

This library publishes the module
`github.com/AtomiCloud/diene.go-standard-config`, materialized from the `go-lib`
template. Retargeting a child changes the final identity token in
`.config/go-lib.yaml`, `go.mod`, mirror URLs, badges, documentation, and its
usage-skill namespace. The mirror remains a single-module repository unless a
concrete library proves otherwise.

It consumes its published siblings through the Go proxy — never a local
`replace` or path dependency — so its own test suites are the family's
downstream real-consumption evidence for
`github.com/AtomiCloud/diene.go-config` and
`github.com/AtomiCloud/diene.go-otel`. `tests/unit/compose` composes a service
root schema from config's app block, otel's engine-owned block, and this
library's four infra presets, then drives the real three-layer load; if either
registry artifact changes, that suite is what turns red.

Before tagging, run `./scripts/validate/go-proxy-roundtrip-dryrun.sh`. It
compiles and runs the exact consumer payload of
`scripts/validate/go-proxy-roundtrip.sh` against the working tree, because the
published script only ever runs against a real tag: a compile error inside it
passes branch CI and first surfaces as a red CD after the tag exists and can no
longer be unpublished.

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

The public packages are `lib/standardconfig` and the consumer-facing
`testhelper`. This library binds no infrastructure of its own — it publishes
schema fragments, and the containers it starts belong to the consumer's tests —
so it ships no `adapters/` tree and its integration tier is a documented no-op;
the container runtime is a seam the meta tier substitutes. The module has no
`main` or `cmd` package. `go build ./...`, `go vet ./...`, golangci-lint, govulncheck,
strict deadcode, examples, and `gorelease` protect the resulting library shape.

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
