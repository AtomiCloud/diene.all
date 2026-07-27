# Go baseline

This repository is the Go language foundation inherited by Go services,
operators, and library templates. It adds language machinery only; application
behavior, observability wiring, environment profiles, and publishing belong to
downstream nodes.

## Toolchain

The Nix shells provide Go 1.26.5, golangci-lint, govulncheck, deadcode,
staticcheck, gofumpt, and gotestsum. Go 1.26.5 is an explicit patch-level
override of the shared 26.05 package because govulncheck rejects Go 1.26.4 for
GO-2026-5856. The override remains source-pinned and carries no vulnerability
exclusion.

## Repository shape

- `lib/` contains pure domain packages.
- `adapters/` contains dependency implementations.
- `cmd/go-base/` is the single composition root and wires concrete adapters
  explicitly.
- `tests/unit/` imports domain packages only through their public API.
- `tests/int/` proves adapters against real dependencies with
  testcontainers-go.

The Note/Redis code is a replaceable sample fenced by these structural
directories. Downstream templates may replace the sample while retaining the
same gates and tier boundaries.

## Commands

- `pls setup` installs modules and synchronizes vendored skills.
- `pls build` creates `dist/go-base`.
- `pls typecheck` compiles source packages without running tests.
- `pls test`, `pls test:unit`, and `pls test:int` run the tiered suites.
- `pls test:coverage`, `pls test:unit:coverage`, and
  `pls test:int:coverage` enforce the scoped ledgers.
- `pls test:watch` watches the unit tier.
- `pls deadcode` runs whole-repository and production-only strict passes, then
  writes the nonblocking review feed to `reports/deadcode-llm.txt`.
- `pls run -- slug "Hello World"` runs from source.
- `pls preview -- slug "Hello World"` runs the compiled artifact.
- `pls up` and `pls down` manage the local Redis dependency.

There is deliberately no `pls dev`: this base is not a long-running server, so
an Air hot-reload loop would add machinery without a real use case.

## Test and coverage law

Every `*_test.go` file must declare a package ending in `_test`, and
`export_test.go` is forbidden. Unit coverage includes only `lib/**` and must be
100%. Integration coverage includes only `adapters/**` and must be 100% in this
minimal base. The checked-in ledger is `.config/go-base.coverage.yaml`; Codecov
flags are informational and carry forward independently.

## Deadcode and vulnerability law

The whole-repository pass runs deadcode with tests enabled and staticcheck with
test analysis. The production pass disables test reachability so a symbol used
only by tests fails. Neither pass has an exclusion list. Govulncheck is a
blocking CI-only job; its negative proof routes a pinned vulnerable fixture
through a deterministic scanner double, while the healthy path uses the real
vulnerability database.

## Template-maintenance boundary

Downstream authors may adapt package/module identity, sample domain code,
coverage thresholds after adding real surface, and README
badges. They must preserve black-box tests, tier scoping,
both deadcode passes, the CI-only vulnerability gate, one composition root,
and generated hook/probe coverage.
