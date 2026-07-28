---
id: dotnet-lib-baseline
title: .NET Library Baseline
---

# .NET library baseline

This branch turns the `.NET 10` base into a publishable library template. It
keeps the base `App` as a non-packable consumer and publishes two lockstep
packages from one solution:

- `AtomiCloud.Diene.ServerEngine` contains the MVC server wiring;
- `AtomiCloud.Diene.ServerEngine.TestHelper` contains the in-process controller
  host, the webhook signer, and the tri-state assertions, and references the main
  package.

Both package ids and assembly names are consumer-visible, real identities.
`dotnet-base.slnx`, `.config/dotnet-base.test.yaml`, workflows, and non-shipped
namespaces stay base-named for merge stability.

## Pack and validate

`Version.props` is the sole version manifest. The root build props import it,
so normal build and pack invocations produce both packages at the same version.

```bash
nix develop .#ci -c ./scripts/ci/pkg-validate.sh
```

The validation entrypoint restores dependencies, packs the solution, requires
the two `.nupkg` and two `.snupkg` artifacts, validates README/icon/license/
repository metadata and portable PDB contents, then restores both package ids
into a scratch .NET 10 project and RUNS it. A scratch consumer that only
compiled would prove the public surface resolves; running it proves the shipped
assemblies actually compose a host, mount their routes, and enforce the webhook
signature contract, which is what a consumer installs them for. Both the local
artifact folder and nuget.org are supplied as restore sources, because these
packages depend on published Diene packages and a local-only source cannot
resolve the transitive graph. `EnablePackageValidation` is active; releases
after 1.0 compare their public API with the `1.0.0` baseline.

## Testing tiers

- `pls test:unit` measures the real `AtomiCloud.Diene.ServerEngine` assembly plus the
  inherited `[Lib*]*` scaling wildcard at 100%, and explicitly excludes
  `*.TestHelper` assemblies.
- `pls test:int` drives the demo consumer over a real Kestrel socket and measures
  only `[App*]*`. It replaces the base Testcontainers adapter boundary: this
  library has no database adapter, and what a TestServer cannot show is the real
  transport.
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
- `skills/diene-dotnet-server-engine-usage/` as the materialized library's
  namespaced usage skill.

Keep CPM, SDK SourceLink, symbols, committed versioning, package validation,
API-key publishing, scratch consumption, and the three coverage ledgers intact.
The all-project dead-code pass includes TestHelper; the production-only pass
keeps the inherited `App*`/`Lib*` runtime boundary. No exclusion list is
permitted.
