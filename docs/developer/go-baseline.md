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
- `tests/sit/` exercises compiled artifacts from a client's perspective.

The Note/Redis code is a replaceable sample fenced by `DOMAIN WIRING` and
`END DOMAIN WIRING` comments in `lib/note/note.go`, `lib/note/service.go`,
`adapters/kv/redis.go`, and `cmd/go-base/main.go`, with matching boundaries in
`tests/unit/note/note_test.go`, `tests/int/kv/redis_test.go`, and
`tests/sit/cli/cli_test.go`. Downstream templates may replace only the bytes
inside those fences while retaining the same gates and tier boundaries.

## Commands

- `task setup` installs modules and synchronizes vendored skills.
- `task build` creates `dist/go-base`.
- `task typecheck` compiles source packages without running tests.
- `task test`, `task test:unit`, `task test:int`, and `task test:sit` run the
  tiered suites; `task test:sit` runs the compiled-artifact Redis journey.
- `task test:coverage`, `task test:unit:coverage`, and
  `task test:int:coverage` enforce the scoped ledgers.
- `task test:watch` watches the unit tier.
- `task deadcode` runs staticcheck and deadcode independently across the
  whole-repository and production-only scopes, then writes the nonblocking
  review feed to `reports/deadcode-llm.txt`.
- `task run -- slug "Hello World"` runs from source.
- `task preview -- slug "Hello World"` runs the compiled artifact.
- `task up` and `task down` manage the local Redis dependency.

There is deliberately no `task dev`: this base is not a long-running server, so
an Air hot-reload loop would add machinery without a real use case.

## Test and coverage law

Every `*_test.go` file must declare a package ending in `_test`, and
`export_test.go` is forbidden. Unit coverage includes only `lib/**` and must be
100%. Integration coverage includes only `adapters/**` and must be 100% in this
minimal base. The checked-in ledger is `.config/go-base.coverage.yaml`; Codecov
flags are informational and carry forward independently.

## Deadcode and vulnerability law

Four independently invoked strict components cover unused code: staticcheck and
deadcode each run once with test analysis/reachability enabled and once against
production packages only. The production deadcode component therefore rejects
a symbol reachable only from tests. None of the components has an exclusion
list. Govulncheck is a blocking CI-only job; its negative proof routes a pinned
vulnerable fixture through a deterministic scanner double, while the healthy
path uses the real vulnerability database.

## Docker and Helm

The Dockerfile builds a static binary and runs it from
`gcr.io/distroless/static-debian12:nonroot` as UID/GID 65532. Separate policy
checks enforce the runtime base and user. The root chart remains a minimal
all-yes Helm surface and is intentionally independent of downstream service
chart design.

## Template-maintenance boundary

Downstream authors may adapt package/module identity, sample domain code,
coverage thresholds after adding real surface, the Docker entrypoint, chart
metadata, and README badges. They must preserve black-box tests, tier scoping,
all four staticcheck/deadcode components, the CI-only vulnerability gate, one
composition root, distroless nonroot runtime policy, and generated hook/probe
coverage.
