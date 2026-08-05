---
id: dotnet-baseline
title: .NET Baseline
---

# .NET baseline

`dotnet-base` is the .NET 10 foundation for the dotnet template family. It
replays the real `AtomiCloud/diene.dotnet-base` sample while retaining the current
shared workspace, standards, Docker, Helm, secret, and release surfaces.

## Local commands

| Command                            | Purpose                                                        |
| ---------------------------------- | -------------------------------------------------------------- |
| `task setup`                       | Synchronize vendored skills and restore repo-local .NET tools. |
| `task clean`                       | Remove build and test artifacts.                               |
| `task build`                       | Build every project in Release.                                |
| `task dev`                         | Run the App through `dotnet watch`.                            |
| `task run -- <args>`               | Run the App in development mode.                               |
| `task preview -- <args>`           | Build and run the compiled Release artifact.                   |
| `task up` / `task down`            | Start or stop the local Redis dependency.                      |
| `task test`                        | Run unit and integration tiers.                                |
| `task test:unit` / `task test:int` | Run one tier.                                                  |
| `task test:unit:coverage`          | Enforce the merged unit coverage ledger.                       |
| `task test:int:coverage`           | Enforce the merged integration coverage ledger.                |
| `task test:unit:watch`             | Watch the fast unit tier.                                      |
| `task deadcode`                    | Emit the broad, non-blocking LLM review.                       |
| `task lint`                        | Run every generated pre-commit hook.                           |

## Projects and coverage

`dotnet-base.slnx` contains `App`, `Lib`, `UnitTest`, and `IntTest`. Register test
projects once in `.config/dotnet-base.test.yaml`. The coverage runner iterates the
registered projects, merges Coverlet JSON, and enforces one final threshold per
tier:

- unit: every `[Lib*]*` assembly at 100%;
- integration: every `[App*]*` assembly at 80%.

The runner then parses the merged `coverage.cobertura.xml` with `xmlstarlet`: it
rejects a report that measured zero lines, rejects any package whose assembly name
escapes the tier ledger, and re-checks the tier minimum against every package's own
`line-rate` rather than the merged total alone.

Adding `Lib2` and `UnitTest2` requires one solution line per project and one YAML
list entry for `UnitTest2`. Assembly filters, merged thresholds, Codecov globs,
and production dead-code project discovery follow the naming convention
automatically. Codecov remains informational.

## Dead code and supply chain

CI runs two strict dn-inspect mechanisms: all projects, then production-only
`App*`/`Lib*` projects so exports reachable only from tests still fail. Local
`task deadcode` uses a deliberately broad filter and never blocks. Exclusion lists
are forbidden.

The SDK is pinned by `global.json`; packages use Central Package Management.
`NuGetAuditMode=all`, analyzers, deterministic builds, and warnings-as-errors are
enforced in Release builds.

`nix/dotnet-deps.json` pins the NuGet closure used by the reproducible Nix
restore. Regenerate it after changing a project package reference, a central
package version, or the pinned SDK:

```bash
nix_system="$(nix eval --impure --raw --expr builtins.currentSystem)"
nix build ".#checks.${nix_system}.pre-commit-check.fetch-deps"
./result nix/dotnet-deps.json
```

The command exposes `buildDotnetModule.passthru.fetch-deps`; its output replaces
`nix/dotnet-deps.json`.

## Docker, Helm, and release

The Dockerfile is a minimal non-root stub, and the Helm chart keeps an empty
template directory for descendants to replace. The Helm axis is complete:
lint/docs hooks, local tasks, OCI packaging, CI/CD jobs, and dependabot coverage
are all active. Releaser stamps the version in `App/App.csproj`; its canonical
`atomi_release.yaml` is the single commit-type vocabulary.

## Template-maintenance boundary

Downstream nodes may adapt package/artifact identity, coverage thresholds, Docker
runtime, chart contents, badges, and the illustrative Note source/tests. Keep
`dotnet-base.slnx`, `.config/dotnet-base.test.yaml`, and the
`AtomiCloud.DotnetBase.*` root namespaces base-named for merge stability.

Observability is deliberately absent on this branch and arrives only through the
separate observability add-back.
