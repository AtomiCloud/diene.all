---
id: dotnet-lib-baseline
title: .NET Library Baseline
---

# .NET library baseline

This branch turns the `.NET 10` base into a publishable library template. It
keeps the base `App` as a non-packable consumer and publishes two lockstep
packages from one solution:

- `AtomiCloud.Diene.Note` contains the illustrative Note domain;
- `AtomiCloud.Diene.Note.TestHelper` contains consumer assertions and references
  the main package.

Both package ids and assembly names are consumer-visible, real identities.
`dotnet-base.slnx`, `.config/dotnet-base.test.yaml`, workflows, and non-shipped
namespaces stay base-named for merge stability.

## Pack and validate

`Version.props` is the sole version manifest. The root build props import it,
so normal build and pack invocations produce both packages at the same version.

```bash
nix develop .#ci -c ./scripts/ci/pkg-validate.sh
```

The validation entrypoint restores dependencies, packs the solution, requires a
`.nupkg` and a `.snupkg` for every packable project, validates README/icon/
license/repository metadata and portable PDB contents, then restores both
package ids into a scratch .NET 10 project.

`scripts/validate/dotnet-package.sh` derives every identity it asserts. Package
ids come from the `IsPackable` projects listed in the root `.slnx`, the expected
artifact count from how many of those there are, the project and repository URLs
from `Directory.Build.props`, and the shipped skill paths from `skills/`. A
materialized library therefore never edits this validator.

`EnablePackageValidation` is always on. `PackageValidationBaselineVersion` is
`1.0.0`, but only while the build is _not_ producing `1.0.0` itself:

```xml
<PackageValidationBaselineVersion Condition="'$(Version)' != '1.0.0'">1.0.0</PackageValidationBaselineVersion>
```

The baseline package does not exist until the library's own first release, so an
unconditional pin makes a fresh materialization unrestorable (`NU1101`). With
the condition, the first release packs without a baseline and every release
after it compares its public API against `1.0.0`. Because the committed manifest
stays at `1.0.0` in-branch, `probes/dotnet-lib-api-compatibility.ts` packs with
`-p:Version=1.0.1` so the gate exercises the state that actually ships.

## Testing tiers

- `pls test:unit` measures the real `AtomiCloud.Diene.Note` assembly plus the
  inherited `[Lib*]*` scaling wildcard at 100%, and explicitly excludes
  `*.TestHelper` assemblies. The scope guard in
  `scripts/local/dotnet-test.sh` reads the allowed assembly names from the
  `AssemblyName` each `Lib*` project declares, so it scales with a renamed
  library instead of naming one.
- `pls test:int` retains the base Testcontainers-backed adapter boundary and
  measures only `[App*]*`.
- `pls test:meta` independently measures `[*.TestHelper]*` at 100%. Its tests
  include known-good and known-bad assertion cases.

Codecov uploads the `unit`, `int`, and `meta` ledgers as informational flags;
the local merged thresholds remain authoritative.

## Release and publish

Semantic release runs `scripts/release/bump.sh`, which first restores
`Version.props` from `HEAD` and then performs one structured XML update. The
release commit includes `Version.props`, `Changelog.md`, and
`docs/developer/CommitConventions.md`.

The `v*.*.*` CD workflow supplies the org `NUGET_API_KEY` to
`scripts/ci/publish.sh`. That script verifies the committed manifest equals the
tag, packs without a version override, and pushes both normal and symbol
packages with `--skip-duplicate`. It never mutates the manifest. Publishing is
performed only by tag-triggered remote CD.

## Promotion knobs

A materialized library changes only these owned surfaces:

- `PackageId`, `AssemblyName`, `RootNamespace`, and `Description` in both
  packable projects;
- shared author/company/repository URLs in `Directory.Build.props`;
- README badges, install snippet, icon, and illustrative source/tests;
- unit/meta thresholds when the shipped surface justifies a stricter value;
- `skills/diene-dotnet-note-usage/` to the materialized library's namespaced
  usage skill.

`scripts/local/dotnet-test.sh`, `scripts/validate/dotnet-package.sh`, and the
package-validation baseline are **not** promotion knobs. They read identity from
the projects and props above, and a materialization that edits them is moving a
hardcode rather than removing one.

Keep CPM, SDK SourceLink, symbols, committed versioning, package validation,
API-key publishing, scratch consumption, and the three coverage ledgers intact.
The all-project dead-code pass includes TestHelper; the production-only pass
keeps the inherited `App*`/`Lib*` runtime boundary. No exclusion list is
permitted.
