---
id: ci-cd
title: CI/CD Workflows
---

# CI/CD Workflows

GitHub Actions supplies triggers, permissions, runners, and inputs. Repository
logic stays in executable `scripts/ci/*.sh` files and runs through the matching
Nix shell.

## Workflow split

| Workflow  | Trigger                            | Responsibility                         |
| --------- | ---------------------------------- | -------------------------------------- |
| `CI`      | pushes, pull requests, manual runs | pre-commit, Docker, and Helm lanes     |
| `Release` | successful `CI` run on `main`      | semantic versioning and GitHub release |
| `CD`      | one `v*.*.*` tag pattern           | versioned Docker image and Helm chart  |

Callers grant permissions, pass only repository-specific values, and use
`secrets: inherit`. Reusable workflows own setup and invoke exactly one existing
CI script. The `a-workflow-wiring` gate enforces that every orchestrator job
resolves to a repository-local reusable workflow and that each reusable workflow
calls an existing, executable `scripts/ci` entry point. The `a-cache-tags` gate
enforces that the selected runner and Namespace cache tag satisfy the S31 shape
below.

## Reusable workflows

- `⚡reusable-precommit.yaml` runs `scripts/ci/pre-commit.sh` in `.#ci`.
- `⚡reusable-docker.yaml` runs `scripts/ci/docker.sh` in `.#cd`.
- `⚡reusable-helm.yaml` runs `scripts/ci/helm.sh` in `.#cd`.
- `⚡reusable-release.yaml` runs `scripts/ci/release.sh` in `.#releaser`.

`AtomiCloud/actions.setup-nix@v3` checks out the repository, so do not add an
adjacent `actions/checkout`. Docker additionally uses
`AtomiCloud/actions.setup-docker@v2`.

## Pins and runners

Trusted actions (`AtomiCloud/`, `actions/`, `codecov/`, and `docker/`) use major
pins. Every other action uses an exact 40-character SHA plus its tag in a
trailing comment. Classification lives in `config/action-trust.json`.

Runner selection is 26.04-first. GitHub-hosted jobs select `ubuntu-26.04`.
Namespace jobs use one of two deliberate venues: cache-eligible Nix-store users
select `nscloud-ubuntu-26.04-amd64-16x32-with-cache`; lanes that must not share
cache state select the bare `nscloud-ubuntu-26.04-amd64-16x32`. The only
permitted fallbacks are the corresponding `ubuntu-24.04` and Namespace 24.04
labels. A job that selects a fallback records a non-empty reason in job-level
`env.S31_RUNNER_FALLBACK_REASON`; primary jobs do not carry that fallback
record. Primary and fallback Namespace venue labels are never combined.

Cache-eligible Namespace Nix jobs carry exactly one shared OS-sensitive tag and
the `nscloud-cache-size-50gb` label. The two valid cached label/tag pairs are:

```text
nscloud-ubuntu-26.04-amd64-16x32-with-cache
nscloud-cache-tag-atomi-nix-store-cache-ubuntu-26.04-amd64

nscloud-ubuntu-24.04-amd64-16x32-with-cache
nscloud-cache-tag-atomi-nix-store-cache-ubuntu-24.04-amd64
```

The organization stays constant; only runner OS and architecture vary. An OS
change rotates the tag and starts with one cold build before warm reuse. Never
alias or carry a 24.04 cache into 26.04, and never introduce per-platform or
per-service cache tags. Must-not-share-cache Namespace lanes use the matching
bare venue label with no cache-size or cache-tag label; cache absence is part of
their isolation contract.

Which jobs are cache-eligible is read from what a job does, not from the labels
it carries. A step's `uses:` is matched as text, so a Nix setup action always
makes a job a Nix-store user. A step's `run:` is a shell script, and the gate
reads it with a small shell lexer that gives one of **three** answers:

- **Nix** — a supported Nix command definitely runs. The command word is
  `nix` **followed immediately by** `develop`, `build`, `shell`, `run`, `flake`,
  `profile` or `store`, or it is legacy `nix-build`, `nix-shell` or `nix-store`.
  Assignments, redirections, keywords, plain wrappers (`sudo nix build`),
  subshells, process substitution and `sh -c '…'` (including combined flags such
  as `bash -lc '…'`) are all read through.
- **Not Nix** — the script definitely runs no Nix command. A mention is not an
  invocation: `echo nix develop`, a comment, quoted text, heredoc content, an
  array literal `args=(nix develop)`, an arithmetic expression, and a `case`
  branch pattern — `nix-build)` with or without its opening parenthesis — are all
  data.
- **Cannot be read** — the script uses syntax the gate will not guess at:
  - an expanded command name (`$CMD develop`), backticks, `eval`, an unterminated
    quote or heredoc;
  - a wrapper with options (`sudo -u root nix develop`), where which word is the
    command depends on what the option consumes;
  - **any first argument to `nix` other than a supported subcommand** — a version
    flag before `develop` still only prints a version, and `nix eval` is real
    store use, so an option and an unrecognised subcommand are both refused;
  - a **function or alias definition** that could carry the invocation:
    `helper() { nix develop; }` may never be called, and
    `alias helper='nix develop'` renames it, so neither is proof either way;
    an ordinary assignment is different: its literal value is data, so
    `FOO=nix nix develop` is read through and invokes Nix;
  - a Nix command name handed to a command that is not on the small inert list —
    `timeout 10m nix build`, `git nix develop`, `bun run nix`,
    `awk 'BEGIN { system("nix develop") }'`, `./runner.sh 'nix develop'`. Only
    commands that demonstrably do not execute their arguments (`echo`, `printf`,
    `grep`, `test`, `case`, `cat`, …) treat such a name as text; anything that can
    delegate execution does not.

The third answer is **refused on every venue** — cached, bare and GitHub-hosted —
and is the point of having three answers rather than two. Calling an unreadable
script "not Nix" would be safe on a cache-capable venue and unsafe on the bare
one, where it would silently excuse a real Nix job from both the cache labels and
the exemption marker below. The gate declines to guess instead. Only a Nix setup
action resolves it; the alternative is to write the command so it can be read.

A Nix-store user on the bare venue also records a non-empty job-level
`env.S31_CACHE_EXEMPT_REASON`, so a deliberate isolation lane is distinguishable
from a lane that lost its cache by accident. That exemption is only meaningful on
the bare Namespace venue: a Nix-store user on a GitHub-hosted runner is rejected
whether or not it records one, and a job that uses no Nix store may neither claim
the shared cache nor record an exemption from it.

## Local reproduction

Use the same entry points as CI:

```bash
nix develop .#ci -c ./scripts/ci/pre-commit.sh
nix develop .#cd -c ./scripts/ci/docker.sh
nix develop .#cd -c ./scripts/ci/helm.sh
```

The Docker and Helm scripts build locally by default. Their reusable workflows
set the documented environment contract to enable publishing.

## Artifact publishing

Docker and Helm callers pass per-repository image or chart values through
workflow `with:` inputs. Empty release versions produce commit builds; CD passes
the tag as the version. Add another image or chart as another caller job rather
than putting repository-specific branching into the reusable workflow.

Release execution is wired now but awaits the C2 step-2p `tools/releaser` fold;
the workspace does not claim a working `releaser` binary before then.
