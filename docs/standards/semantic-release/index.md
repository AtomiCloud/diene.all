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

The configuration is live, and **nothing validates it.** There is no schema gate on
`atomi_release.yaml`: the validator and the hook that ran it were removed, because
they enforced a policy no released tool consumes yet. The file itself is therefore
the only authority — if you break its shape, you find out when a release runs, not
when you commit.

Running a release does not work here yet either — not because the `releaser` binary is
missing in the world, but because no development shell in this repository provides it.
Concretely:

- release execution is fully wired — the workflow, the release Nix shell, and
  `scripts/ci/release.sh` all exist — but the command at the end of that chain
  resolves to nothing on this repository's `PATH`, so it cannot run here;
- no hook checks commit messages against the types below; see
  [the linting standard](../linting/index.md);
- `sg` sits in the release shell as a temporary bootstrap dependency, and leaves
  once `releaser` is published.

## How releases are configured

The plugin chain is the `plugins:` list in `atomi_release.yaml`. Each entry names
its `module:`, its pinned `version:`, and — when the plugin needs settings — a
`config:` block holding that plugin's own settings: which files it writes, which it
commits, and what commands it runs. An entry with no `config:` is a plugin running
on its defaults. Read the list in order; the order is itself part of the contract.

Two entries carry a note worth reading before you edit them:

- `@semantic-release/exec` is present with no `config:` **on purpose**. Every step of
  that plugin is skipped unless the matching `*Cmd` is set, so it costs nothing and
  stands as the hook point a downstream node fills in — usually with a `prepareCmd`
  that stamps the version into whatever file that node's ecosystem versions. This
  workspace versions no such file, so it sets no command.
- `@semantic-release/git` lists in `assets` the files a release commits. If you add a
  `prepareCmd` that writes a file, add that file here in the same edit; a file that is
  stamped but not listed is never committed, and a file listed but never stamped is
  dead configuration.

Commit types and release calculation read this same configuration, so there is only
one vocabulary to keep correct.

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
releaser conventions
releaser release -c atomi_release.yaml
```

`releaser conventions` maintains the file named by `conventionMarkdown.path` in
`atomi_release.yaml`. Once it can run, that file is generated output and must not
be edited by hand.
