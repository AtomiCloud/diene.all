---
id: dotnet-baseline
title: .NET Baseline
---

# .NET baseline

`dotnet-base` is the .NET 10 foundation for the dotnet template family. It
replays the real `AtomiCloud/diene.dotnet-base` sample while retaining the current
shared workspace, standards, secret, and release surfaces.

## Local commands

| Command                          | Purpose                                                        |
| -------------------------------- | -------------------------------------------------------------- |
| `pls setup`                      | Synchronize vendored skills and restore repo-local .NET tools. |
| `pls clean`                      | Remove build and test artifacts.                               |
| `pls build`                      | Build every project in Release.                                |
| `pls dev`                        | Run the App through `dotnet watch`.                            |
| `pls run -- <args>`              | Run the App in development mode.                               |
| `pls preview -- <args>`          | Build and run the compiled Release artifact.                   |
| `pls up` / `pls down`            | Start or stop the local Redis dependency.                      |
| `pls test`                       | Run unit and integration tiers.                                |
| `pls test:unit` / `pls test:int` | Run one tier.                                                  |
| `pls test:coverage`              | Enforce both merged coverage ledgers.                          |
| `pls test:watch`                 | Watch the fast unit tier.                                      |
| `pls deadcode`                   | Emit the broad, non-blocking LLM review.                       |
| `pls lint`                       | Run every generated pre-commit hook.                           |

## Projects and coverage

`dotnet-base.slnx` contains `App`, `Lib`, `UnitTest`, and `IntTest`. Register test
projects once in `.config/dotnet-base.test.yaml`. The coverage runner iterates the
registered projects, merges Coverlet JSON, and enforces one final threshold per
tier:

- unit: every `[Lib*]*` assembly at 100%;
- integration: every `[App*]*` assembly at 80%.

Adding `Lib2` and `UnitTest2` requires one solution line per project and one YAML
list entry for `UnitTest2`. Assembly filters, merged thresholds, Codecov globs,
and production dead-code project discovery follow the naming convention
automatically. Codecov remains informational.

## Dead code and supply chain

CI runs two strict dn-inspect mechanisms: all projects, then production-only
`App*`/`Lib*` projects so exports reachable only from tests still fail. Local
`pls deadcode` uses a deliberately broad filter and never blocks. Exclusion lists
are forbidden.

The SDK is pinned by `global.json`; packages use Central Package Management.
`NuGetAuditMode=all`, analyzers, deterministic builds, and warnings-as-errors are
enforced in Release builds.

## Release

The library descendant replaces the base `VERSION` marker with its imported
`Version.props` package manifest. `.gitlint` and `atomi_release.yaml` share one
commit-type vocabulary.

## Template-maintenance boundary

Downstream nodes may adapt package/artifact identity, coverage thresholds,
badges, and the illustrative Note source/tests. Keep
`dotnet-base.slnx`, `.config/dotnet-base.test.yaml`, and the
`AtomiCloud.DotnetBase.*` root namespaces base-named for merge stability.

Observability is deliberately absent on this branch and arrives only through the
separate observability add-back.
