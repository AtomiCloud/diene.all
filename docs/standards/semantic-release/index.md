---
id: semantic-release
title: Semantic Release
---

# Semantic Release

`atomi_release.yaml` is the single source of truth for commit types, release
levels, generated commit-convention documentation, and the semantic-release
plugin chain. Do not add a standalone `.gitlint` file.

## Build-order boundary

The workspace baseline registers the future commands now. The full `releaser`
binary is published by `tools/releaser` at C2 step 2p; until that fold lands a
temporary Nix-shell bootstrap shim stands in for the release surface only:

- the repository-owned validators check the configuration schema, plugin chain,
  and exact D3 type vocabulary;
- the `.#releaser` shell exposes a `releaser` command that delegates **only the
  release surface** to `sg` — `releaser release -c <cfg>` dispatches to
  `sg release -c <cfg>` — so `scripts/ci/release.sh` runs without the earlier
  missing-executable failure;
- `releaser lint-commit` and `releaser conventions` remain explicitly deferred:
  `sg` has no equivalent subcommand, so the commit-msg hook stays registered as
  `releaser lint-commit -c atomi_release.yaml` but is not yet functional, and
  the generated `docs/developer/CommitConventions.md` keeps its bootstrap
  notice; and
- `sg` is present only as that temporary bootstrap dependency, reached through
  the `releaser` release surface rather than invoked directly.

After step 2p, `tools/releaser` replaces the bootstrap shim and every registered
command — `lint-commit`, `conventions`, and `release` — becomes executable under
the single `releaser` name.

## Commands

```bash
releaser lint-commit -c atomi_release.yaml <commit-message-file>
releaser conventions
releaser release -c atomi_release.yaml
```

`releaser conventions` maintains
`docs/developer/CommitConventions.md`. The generated file must not be edited by
hand.

## Configuration

The base plugin order is fixed:

1. `@semantic-release/changelog`
2. `@semantic-release/exec`
3. `@semantic-release/git`
4. `@semantic-release/github`

Plugin versions are pinned in `atomi_release.yaml`. The exec plugin updates
`VERSION`; the git plugin commits `Changelog.md`, `VERSION`, and the generated
commit-conventions document.

Go libraries are the sanctioned no-manifest variance: semantic release keeps
the changelog, git, and GitHub plugins but has no exec stamp and no `VERSION`
asset. The committed `vX.Y.Z` tag is the module version served by the Go proxy.

The unified D3 commit-type vocabulary is:

```text
amend, build, chore, ci, config, dep, docs, feat, fix, perf, refactor, style, test
```

Both commit validation and release calculation consume this same configuration,
so the vocabularies cannot drift independently.

## Workflow

1. `CI` completes successfully on `main`.
2. `release.yaml` starts through `workflow_run` with concurrency group
   `release`.
3. `scripts/ci/release.sh` runs inside `nix develop .#releaser`.
4. `releaser release -c atomi_release.yaml` calculates the version, updates the
   changelog and generated files, creates the tag, and publishes the GitHub
   release.

The release surface is executable pre-2p through the bootstrap shim
(`releaser release` dispatches to `sg release`); the `tools/releaser` fold at C2
step 2p replaces the shim with the first-class binary and lifts the remaining
`lint-commit` and `conventions` deferrals.
