---
id: dotnet-lib-baseline
title: .NET Library Baseline
---

# .NET library baseline

This CoreUtils materialization keeps `App` as a non-packable demo consumer and
publishes ONE package from the solution:

- `AtomiCloud.Diene.CoreUtils` contains the C0 wire codecs, the slug and
  namespaced-key helpers, `KeyNormalizer`, and the `WireAttributes` bridge onto
  the seams declared by `AtomiCloud.Diene.Interfaces`.

There is no TestHelper companion here — the usefulness lens says NO for a pure
value library. The dual-package machinery stays inherited and dormant: the meta
tier deactivates itself when no `TestHelper*.csproj` exists, so `pls test:meta`
is a green no-op and no empty `meta` flag reaches codecov. The shipped usage
skill carries the steps to add one later.

The package id and assembly name are consumer-visible, real identities.
`dotnet-base.slnx`, `.config/dotnet-base.test.yaml`, workflows, and non-shipped
namespaces stay base-named for merge stability.

## Pack and validate

`Version.props` is the sole version manifest. The root build props import it,
so normal build and pack invocations produce the package at the committed version.

```bash
nix develop .#ci -c ./scripts/ci/pkg-validate.sh
```

The validation entrypoint restores dependencies, packs the solution, requires
exactly one `.nupkg` and one `.snupkg` artifact, validates README/icon/license/
repository metadata and portable PDB contents, then restores the package id into
a scratch .NET 10 project and exercises the shipped surface.
`EnablePackageValidation` is active; releases after 1.0 compare their public API
with the `1.0.0` baseline.

## Testing tiers

- `pls test:unit` measures the real `AtomiCloud.Diene.CoreUtils` assembly plus
  the inherited `[Lib*]*` scaling wildcard at 100%, and explicitly excludes
  `*.TestHelper` assemblies.
- `pls test:int` measures only `[App*]*` and covers what is real only against
  the host: IANA timezone resolution through the machine tz database and the
  pinned C0 fixture read off a real filesystem.
- `pls test:meta` is inactive because no TestHelper project exists. It exits
  green and uploads nothing.

Codecov uploads the `unit` and `int` ledgers as informational flags (`meta` has
no results to upload here); the local merged thresholds remain authoritative.

## Release and publish

Semantic release runs `scripts/release/bump.sh`, which first restores
`Version.props` from `HEAD` and then performs one structured XML update. The
release commit includes `Version.props`, `Changelog.md`, and
`docs/developer/CommitConventions.md`.

The `v*.*.*` CD workflow supplies the org `NUGET_API_KEY` to
`scripts/ci/publish.sh`. That script verifies the committed manifest equals the
tag, packs without a version override, and pushes the normal and symbol packages
with `--skip-duplicate`. It never mutates the manifest. Publishing is
performed only by tag-triggered remote CD.

## Promotion knobs

A materialized library changes only these owned surfaces:

- `PackageId`, `AssemblyName`, `RootNamespace`, and `Description` in each
  packable project;
- shared author/company/repository URLs in `Directory.Build.props`;
- README badges, install snippet, icon, and illustrative source/tests;
- unit/meta thresholds when the shipped surface justifies a stricter value;
- `skills/diene-dotnet-core-utils-usage/` to the materialized library's
  namespaced usage skill.

Keep CPM, SDK SourceLink, symbols, committed versioning, package validation,
API-key publishing, scratch consumption, and the three coverage ledgers intact.
The all-project dead-code pass includes any TestHelper that exists; the
production-only pass keeps the inherited `App*`/`Lib*` runtime boundary. No
exclusion list is permitted.
