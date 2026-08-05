---
id: semantic-release
title: Semantic Release
---

# Semantic Release

## What this covers

`atomi_release.yaml` is the single source of truth for the commit types, the
release level each one produces, the generated commit-convention document, and
the semantic-release plugin chain. Everything about releases in this repository is
configured in that one file. There is no standalone `.gitlint` file and one must
not be added.

## What works today, and what does not

The configuration is live and enforced. `scripts/validate/release-config.sh`
checks its schema, its plugin chain, and its commit-type list, and the
`a-release-config` gate runs that validator on every change to
`atomi_release.yaml`.

Running a release does not work yet, because the `releaser` binary that would
execute one is not published. Concretely:

- release execution is fully wired — the workflow, the release Nix shell, and
  `scripts/ci/release.sh` all exist — but the command at the end of that chain has
  no binary behind it, so it cannot run;
- the `a-releaser-commit` commit-msg hook is registered against this same
  configuration, and is unavailable for the same reason: the registration is real,
  the binary it calls is not there yet;
- `sg` sits in the release shell as a temporary bootstrap dependency, and leaves
  once `releaser` is published.

## How releases are configured

The plugin chain is the `plugins:` list in `atomi_release.yaml`. Each entry names
its `module:`, its pinned `version:`, and a `config:` block holding that plugin's
own settings — which files it writes, which it commits, and what commands it runs.
Read the list in order; the order is itself part of the contract.

Two things in that file are fixed policy rather than free configuration: the base
plugin chain, and the shared commit-type vocabulary. `scripts/validate/release-config.sh`
holds the exact expected values for both, so it is the file to read when you want
to know what the gate will accept — and the file to change, deliberately and
together with `atomi_release.yaml`, when the policy itself should change.

Commit validation and release calculation read this same configuration, so the two
vocabularies cannot drift apart.

## How a release is triggered

Release is its own workflow, and it runs off a successful `CI` run rather than off
a push. `.github/workflows/release.yaml` declares that `workflow_run` trigger, the
restriction to `main`, and the `release` concurrency group; the `a-workflows` gate
pins those values, and `scripts/validate/workflows.sh` holds the exact ones it
expects.

The workflow ends in a single `scripts/ci/release.sh` call inside the `releaser`
Nix shell. That script runs `releaser release`, which calculates the version,
updates the changelog and generated files, creates the tag, and publishes the
GitHub release.

## Commands

These are the commands the `releaser` tool provides. They are recorded here
because the repository is already configured for them — none of them run until
that tool is published.

```bash
releaser lint-commit -c atomi_release.yaml <commit-message-file>
releaser conventions
releaser release -c atomi_release.yaml
```

`releaser conventions` maintains the file named by `conventionMarkdown.path` in
`atomi_release.yaml`. Once it can run, that file is generated output and must not
be edited by hand.
