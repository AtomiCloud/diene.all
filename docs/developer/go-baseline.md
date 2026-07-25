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
- `cmd/manager/` is the single composition root and wires concrete adapters
  explicitly.
- `tests/unit/` imports domain packages only through their public API.
- `tests/int/` proves adapters against real dependencies with envtest.

The Boron operator surface (the `Account`/`Tunnel`/`Exposure` CRDs, pure
reconcile services, and the Cloudflare provider adapter) is fenced by these
structural directories under the same gates and tier boundaries the
operator-template proves once.

## Commands

- `pls setup` installs modules and synchronizes vendored skills.
- `pls build` creates `dist/manager`.
- `pls typecheck` compiles source packages without running tests.
- `pls test`, `pls test:unit`, and `pls test:int` run the tiered suites.
- `pls test:coverage`, `pls test:unit:coverage`, and
  `pls test:int:coverage` enforce the scoped ledgers.
- `pls test:watch` watches the unit tier.
- `pls deadcode` runs whole-repository and production-only strict passes, then
  writes the nonblocking review feed to `reports/deadcode-llm.txt`.
- `pls run -- --help` runs the manager from source.
- `pls preview -- --help` runs the compiled manager artifact.
- `pls operator:generate` regenerates the CRDs, RBAC, and deepcopy from the Go
  types and markers.
- `pls operator:e2e` runs the k3d end-to-end journey (throwaway cluster).

## Test and coverage law

Every `*_test.go` file must declare a package ending in `_test`, and
`export_test.go` is forbidden. Unit coverage includes only `lib/**` and must be
100%. Integration coverage includes only `adapters/**`; the operator's real
adapter surface (controller-runtime reconcilers and the Cloudflare HTTP
adapter) adapts the int threshold below 100 because defensive transport-error
branches are not deterministically reachable with real dependencies — see the threshold
comment in `.config/go-base.coverage.yaml`. Codecov flags are informational and
carry forward independently.

## Deadcode and vulnerability law

The whole-repository pass runs deadcode with tests enabled and staticcheck with
test analysis. The production pass disables test reachability so a symbol used
only by tests fails. Neither pass has an exclusion list. Govulncheck is a
blocking CI-only job; its negative proof routes a pinned vulnerable fixture
through a deterministic scanner double, while the healthy path uses the real
vulnerability database.

## Docker and Helm

The Dockerfile builds a static binary and runs it from
`gcr.io/distroless/static-debian12:nonroot` as UID/GID 65532. Separate policy
checks enforce the runtime base and user. The root chart is the operator manager
chart: CRDs (plain templates), RBAC, the manager Deployment, a secured metrics
Service, and the observability pack (ServiceMonitor, GrafanaAlertRuleGroup, and a
Grafana dashboard).

## Template-maintenance boundary

Downstream authors may adapt package/module identity, sample domain code,
coverage thresholds after adding real surface, the Docker entrypoint, chart
metadata, and README badges. They must preserve black-box tests, tier scoping,
both deadcode passes, the CI-only vulnerability gate, one composition root,
distroless nonroot runtime policy, and generated hook/probe coverage.
