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
job resolves to a repository-local reusable workflow and that each reusable
workflow calls an existing, executable `scripts/ci` entry point.

`AtomiCloud/actions.setup-nix` checks out the repository, so do not add an
adjacent `actions/checkout`.

## Pins and runners

Trusted actions use major pins; every other action uses an exact 40-character SHA
plus its tag in a trailing comment. Which actions are trusted is recorded in
`config/action-trust.json`: each key is an action reference and its value is
`trusted` or `non-trusted`. `scripts/validate/action-pins.sh` reads that file and
fails any action used in a workflow that has no classification, so adding an
action means adding its entry there.

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

The Docker and Helm scripts build locally by default. Their reusable workflows
set the documented environment contract to enable publishing.

## Artifact publishing

Docker and Helm callers pass per-repository image or chart values through
workflow `with:` inputs. Empty release versions produce commit builds; CD passes
the tag as the version. Add another image or chart as another caller job rather
than putting repository-specific branching into the reusable workflow.

Release execution consumes the immutable `AtomiCloud/releaser` v1.0.0 flake
input, so the checked-in release command is available to CI.
