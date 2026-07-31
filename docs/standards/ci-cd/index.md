---
id: ci-cd
title: CI/CD Workflows
---

# CI/CD Workflows

GitHub Actions supplies triggers, permissions, runners, and inputs. Repository
logic stays in executable `scripts/ci/*.sh` files and runs through the matching
Nix shell.

## Reading the workflow set

The workflows are `.github/workflows/`. Two kinds live there, distinguished by
their trigger block:

- **Orchestrators** — a `name:` plus real event triggers (`on.push`,
  `on.pull_request`, `on.workflow_run`). Their jobs do no work themselves: each
  job is a `uses:` pointing at a repository-local reusable workflow, with
  `permissions:`, `secrets: inherit`, and any repository-specific `with:` inputs.
  Read a job's `uses:` to see which lane it runs, and the orchestrator's `on:`
  block to see when.
- **Reusable workflows** — `on.workflow_call` only, named with a `⚡` prefix.
  Each owns runner selection and setup and ends in exactly one `run:` line of the
  form `nix develop .#<shell> -c ./scripts/ci/<script>.sh`. That line is the
  authoritative statement of which script the lane runs and in which shell.

Callers grant permissions, pass only repository-specific values, and use
`secrets: inherit`. The `a-workflows` gate enforces that every orchestrator
job resolves to a repository-local reusable workflow, that each reusable
workflow calls an existing, executable `scripts/ci` entry point, and that the
selected runner and Namespace cache tag satisfy the S31 shape below.

`AtomiCloud/actions.setup-nix` checks out the repository, so do not add an
adjacent `actions/checkout`.

## Pins and runners

Trusted actions use major pins; every other action uses an exact 40-character SHA
plus its tag in a trailing comment. Which actions are trusted is recorded in
`config/action-trust.json`: each key is an action reference and its value is
`trusted` or `non-trusted`. `scripts/validate/action-pins.sh` reads that file and
fails any action used in a workflow that has no classification, so adding an
action means adding its entry there.

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
it carries: a job that uses a Nix setup action or runs a `nix` command is a
Nix-store user. Such a job on the bare venue also records a non-empty job-level
`env.S31_CACHE_EXEMPT_REASON`, so a deliberate isolation lane is distinguishable
from a lane that lost its cache by accident. That exemption is only meaningful on
the bare Namespace venue: a Nix-store user on a GitHub-hosted runner is rejected
whether or not it records one, and a job that uses no Nix store may neither claim
the shared cache nor record an exemption from it.

## Local reproduction

Run the same entry point the lane runs. Take the `run:` line from the reusable
workflow you want to reproduce and run it verbatim, for example:

```bash
nix develop .#ci -c ./scripts/ci/pre-commit.sh
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
