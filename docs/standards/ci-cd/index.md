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
  Each owns runner selection and setup and ends in a `run:` line of the form
  `nix develop .#<shell> -c ./scripts/ci/<script>.sh`. The pre-commit workflow
  additionally runs `skills-sync sync --tier ci` as an explicit step before its
  script: the hook uses the warning tier, so running the hook in CI cannot stand
  in for the guarantee tier.

Callers grant permissions, pass only repository-specific values, and use
`secrets: inherit`. The `a-workflows` gate enforces that every orchestrator
job resolves to a repository-local reusable workflow and that each reusable
workflow calls an existing, executable `scripts/ci` entry point.

`AtomiCloud/actions.setup-nix` checks out the repository, so do not add an
adjacent `actions/checkout`.

## Action pins

Trusted actions use major pins; every other action uses an exact 40-character SHA
plus its tag in a trailing comment. Which actions are trusted is one regex,
`dlint.yaml`'s `checks["action-pins"].trustedPattern`: an action matching it is
trusted, everything else is non-trusted by default — so an action nobody thought
about gets the strictest pin, and there is no list to maintain.

Every nscloud Nix job carries exactly one shared tag:

```text
nscloud-cache-tag-atomi-nix-store-cache-linux-amd64
```

The organization stays constant; only runner OS and architecture vary. Never
introduce per-platform or per-service cache tags.

## Local reproduction

Run the same entry point the lane runs. Take the `run:` line from the reusable
workflow you want to reproduce and run it verbatim, for example:

```bash
nix develop .#ci -c ./scripts/ci/pre-commit.sh
```

A downstream runtime restores its dependencies before the skills step; this node
declares `runtimes: [dart]`, so that restoration is real here rather than inert.

Release execution runs the real tool: `⚡reusable-release.yaml` enters the
`releaser` shell and calls `scripts/ci/release.sh`, which invokes
`releaser release -c release.yaml`. That script clears `.git/hooks` first,
which is not incidental — the release commit's own message uses a `release:` prefix
that is not a configured commit type, so the commit-msg hook would refuse the
release the tool is in the middle of making.
