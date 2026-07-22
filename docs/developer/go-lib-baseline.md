# Go library baseline

This template publishes the module
`github.com/AtomiCloud/diene.go-interfaces`. A materialized child changes the final
`go-lib` token to its library name in `.config/go-lib.yaml`, `go.mod`, mirror
URLs, badges, documentation, and its usage-skill namespace. The mirror remains
a single-module repository unless a concrete library proves otherwise.

## Package and API shape

Keep public packages small and cohesive. Put implementation-only packages under
`internal/`; never expose logic solely for tests. Every exported symbol has a
doc comment, and `Example*` functions are executable consumer documentation.
All tests use external `_test` packages, and `export_test.go` is forbidden.

The public surface lives in `lib/interfaces` (implementation-free system, VFS,
terminal, logging, and metrics seams) with a consumer-facing `testhelper`
package of in-memory mocks. This library depends on the family
errors-problems module for mock fault paths, has no adapters, and leaves the
integration tier empty and no-op. The module has no `main` or `cmd` package.
`go build ./...`, `go vet ./...`,
golangci-lint, govulncheck, strict deadcode, examples, and `gorelease` protect
the resulting library shape.

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
