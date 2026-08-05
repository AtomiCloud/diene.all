---
id: semantic-release
title: Semantic Release
---

# Semantic Release

`atomi_release.yaml` is the single source of truth for commit types, release
levels, generated commit-convention documentation, and `releaser` release
behavior. It uses `schemaVersion: 2`; the legacy semantic-release plugin chain
is forbidden. Do not add a standalone `.gitlint` file.

## Provisioning

The `releaser` binary is the published `AtomiCloud/releaser` `v1.0.0` release,
consumed as a pinned Nix flake input
(`github:AtomiCloud/releaser/v1.0.0#releaser`) and exposed through the `releaser`
package and the `.#releaser` dev shell:

- the repository-owned validators check the configuration schema and the exact
  commit-type vocabulary;
- the commit-msg hook runs `releaser lint-commit -c atomi_release.yaml`; and
- `releaser release -c atomi_release.yaml` executes the release inside
  `nix develop .#releaser`.

## Commands

```bash
releaser lint-commit -c atomi_release.yaml <commit-message-file>
releaser conventions
releaser release -c atomi_release.yaml
```

`releaser conventions` maintains the file named by `conventions.path` in
`atomi_release.yaml`. That generated file must not be edited by hand.

## Configuration

`atomi_release.yaml` uses `schemaVersion: 2`, so there is no `plugins:` list and
no per-plugin `module:`/`version:` pin: one strict configuration replaces the
runtime plugin chain, and nothing loads a plugin or invokes a package manager at
release time. The release pipeline is fixed:

1. write the changelog to `Changelog.md`;
2. run the `afterWrite` hook `scripts/release/bump.sh ${version}`, which stamps
   `package.json`;
3. commit `Changelog.md`, `package.json`, and the generated commit-conventions
   document; and
4. publish the GitHub release.

**The version lives in the language manifest.** `package.json` is the version
record; this repository carries no `VERSION` file, because a second copy of a
number nothing reads goes stale in silence. The releaser stamps no version file
of its own — the repository's `prepare` hook does — so what a hook writes and
what `release.commit.assets` commits are edited together, always. Read
`release.hooks.prepare` and `release.commit.assets` side by side: every stamped
path appears in both.

The commit-type vocabulary and the configuration schema are fixed policy rather
than free configuration. Both are enforced by
`scripts/validate/release-config.sh`, which holds the exact expected values —
read it to see what the `a-release-config` gate will accept. Changing either
means changing the validator and the configuration together, deliberately.

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

Its trigger, branch restriction, and concurrency group are declared in
[`.github/workflows/release.yaml`](../../../.github/workflows/release.yaml) and pinned by the
`a-workflows` gate; `scripts/validate/workflows.sh` holds the exact expected values.
