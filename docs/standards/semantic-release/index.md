---
id: semantic-release
title: Semantic Release
---

# Semantic Release

## What this covers

`atomi_release.yaml` is the single source of truth for the commit types, the
release level each one produces, the message rules the commit-msg hook applies, the
generated commit-convention document, and how a release commits and publishes.
Everything about releases in this repository is configured in that one file. There
is no standalone `.gitlint` file and one must not be added.

The tool that reads it is `releaser`, and it **replaces** semantic-release: there is
no plugin list, no package manager invoked at release time, and no separate
`.releaserc.yaml`. The configuration is `schemaVersion: 2`.

## What works today, and what does not

Everything on this page runs. `releaser` is in the `dev` and `releaser` package
groups, so it is on `PATH` in the default shell and in the release shell:

- commit messages are checked — the `a-releaser-commit` commit-msg hook calls
  `releaser lint-commit`; see [the linting standard](../linting/index.md);
- a release runs end to end from `⚡reusable-release.yaml`;
- the commit-conventions document is generated from this file, not hand-written.

**Nothing runs a schema gate as a separate step**, and it does not need one: every
`releaser` subcommand loads and validates this file before it does anything, and
refuses with the offending field named. The standalone validator script that used to
assert the shape was deleted because it duplicated the tool. Break the file and
`releaser lint-commit` fails on your next commit — which is the earliest place a
check could fire.

## How releases are configured

The configuration is one document with five top-level parts.

- `types:` and `specialScopes:` are the commit vocabulary — each type carries a
  `desc`, an optional changelog `section`, and its scopes with the release level
  each one produces.
- `keywords:` are the breaking-change markers.
- `lint:` holds the message rules `releaser lint-commit` applies: header length,
  forbidden words, trailing punctuation, body line length, and the commit kinds it
  ignores outright (merges, reverts, fixups, squashes).
- `conventions:` names the generated document and carries its `template`. See
  "The generated document" below, because the template is doing more work than it
  looks like.
- `release:` is the release itself: which `branches` may release, the `tagFormat`,
  the `changelog` path and title, the `commit` message and `assets`, whether a
  `github` release is published, and `hooks`.

Two parts of `release:` carry a note worth reading before you edit them:

- `release.hooks.prepare` is **filled here**. It is where the old
  `@semantic-release/exec` hook point moved to: a list of
  `{ phase: beforeWrite | afterWrite, command: … }` entries a downstream node
  fills, usually with an `afterWrite` command that stamps the version into whatever
  file that node's ecosystem versions. This node versions `package.json`, so it
  carries one `afterWrite` entry, `scripts/release/bump.sh ${version}`, and
  `package.json` appears in `assets` because that hook writes it. **The version
  lives in the language manifest and nowhere else** — there is no `VERSION` file,
  because a second copy of a number nothing writes goes stale in silence. The
  releaser stamps no version file of its own; it writes only the changelog and the
  conventions document, so every versioned path here comes from a `prepare`
  command.
- `release.commit.assets` lists the files a release commits, and it is enforced
  rather than advisory: the releaser aborts if a write lands outside the list, and a
  file listed but never written is dead configuration. So if you add a `prepare`
  command that writes a file, add that file to `assets` **in the same edit**.

Commit linting and release calculation read this same configuration, so there is
only one vocabulary to keep correct.

## The generated document

`conventions.path` names `docs/developer/CommitConventions.md` and
`conventions.template` is the page it is generated into: `releaser conventions`
substitutes the generated type and scope tables for `CONVENTION_DOCS_PLACEHOLDER`
and writes the whole thing. A release run writes that same file.

So the template is where a human-readable reading guide has to live. Prose put
straight into the generated file is lost at the next release; prose put into the
template survives every regeneration. The generated tables alone are tables and
nothing else.

That file is excluded from `treefmt` in [`nix/fmt.nix`](../../../nix/fmt.nix), and
the exclusion is load-bearing rather than a leftover: the generator emits unpadded
markdown tables, prettier pads them, and a formatted file would be rewritten
unformatted by the next release — so formatting it would put the release run and the
format gate in permanent disagreement.

## How a release is triggered

Release is its own workflow, and it runs off a successful `CI` run rather than off
a push. `.github/workflows/release.yaml` declares that `workflow_run` trigger, the
restriction to `main`, and the `release` concurrency group; the `a-workflows` gate
pins those values, and `scripts/validate/workflows.sh` holds the exact ones it
expects.

The workflow ends in a single `scripts/ci/release.sh` call inside the `releaser`
Nix shell. That script runs `releaser release -c atomi_release.yaml`, which
calculates the version, writes the changelog and the conventions document, commits
the configured assets, tags, pushes, and publishes the GitHub release.

It clears `.git/hooks` first, and that line is load-bearing: the release commit's
message begins `release:`, which is not one of the configured commit types, so the
commit-msg hook would refuse the commit the tool is in the middle of making.

## Commands

```bash
releaser next                          # the version the current commits would produce
releaser changelog                     # the release notes they would produce
releaser conventions                   # regenerate the commit-conventions document
releaser release --dry-run             # everything a release would do, changing nothing
releaser release -c atomi_release.yaml # the real thing; CI runs this one
```

`releaser release` without `--dry-run` is the only command that changes git or
publishes anything. `next`, `changelog` and `release` all refuse unless the current
branch is listed in `release.branches`, so on a feature branch they report that
rather than guessing.

`releaser conventions` maintains the file named by `conventions.path`. That file is
generated output and must not be edited by hand — edit `atomi_release.yaml` and
regenerate.
