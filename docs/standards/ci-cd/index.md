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
`secrets: inherit`. The `a-workflows` gate enforces that every orchestrator job
resolves to a repository-local reusable workflow, that each reusable workflow
calls an existing, executable `scripts/ci` entry point, and that the release
workflow keeps its trigger and concurrency group.

`AtomiCloud/actions.setup-nix` checks out the repository, so do not add an
adjacent `actions/checkout`.

## Action pins

Trusted actions use major pins; every other action uses an exact 40-character SHA
plus its tag in a trailing comment. Which actions are trusted is recorded in
`config/action-trust.json`: each key is an action reference and its value is
`trusted` or `non-trusted`. On this node the check is
`scripts/validate/action-pins.sh`, run in two modes by the `a-action-pins-trusted`
and `a-action-pins-non-trusted` hooks; it reads that file and refuses any action
used in a workflow that has no classification, so adding an action means adding
its entry there. The parent template runs the same rule through `dlint
action-pins` instead and takes the path from `.dlint.json`'s
`checks["action-pins"].trustMap`; this node's `.dlint.json` configures only
`ci-wiring`, so that key is deliberately absent here.

## Every job declares its dependencies

> **Every `run:` step enters a Nix shell that declares what it needs.**

In practice a `run:` step is exactly one line:

```text
nix develop .#<shell> -c <command>
```

`<shell>` is one of the shells declared in
[`nix/shells.nix`](../../../nix/shells.nix) — today `default`, `ci`, `cd` and
`releaser`. Three things follow: a job's dependencies are visible without reading
the job, CI and your laptop run the same tools, and every job can reuse the shared
Nix store cache.

## Runners and cache labels

These are plain workflow configuration. Nothing validates them, so read the
existing `runs-on:` blocks and copy the shape.

Selection is 26.04-first: GitHub-hosted jobs take `ubuntu-26.04`, Namespace jobs
take `nscloud-ubuntu-26.04-amd64-16x32-with-cache` plus `nscloud-cache-size-50gb`
and the shared store-cache tag `nscloud-cache-tag-nix-store-cache-ubuntu-26.04-amd64`.
The 24.04 equivalents are the fallbacks. A lane that must **not** share the store
uses the bare `nscloud-ubuntu-26.04-amd64-16x32` with no cache labels at all — a
bare label cannot attach a cache volume, which is the point of using it. The cache
is shared per OS and architecture, carries no organization, platform or service
name, and changing the OS rotates the tag and costs one cold build before warm
reuse resumes.

## The pre-vendor hook

Every lane starts at `scripts/ci/setup.sh`, which vendors each dependency's skills
before anything else runs. `skills-sync sync --tier setup` validates the explicit
no-runtime contract.
package manager's own on-disk cache, so it can only see packages that have already
been materialised there.

> **Before skills are vendored, each ecosystem gets one chance to materialise its
> declared packages.** An ecosystem that takes it makes the vendor tree a function
> of the declared dependency set. An ecosystem that does not may vendor a partial
> tree, and the `a-skills-sync` gate then fails several steps later on a diff
> that does not name this as the cause.

The hook is an optional executable at `scripts/ci/pre-vendor.sh`. `setup.sh` runs
it, if it is there, immediately before `skills-sync.sh`. There is nothing to
configure and no workflow to edit: a lane that already calls `setup.sh` picks the
hook up by the file existing.

This template declares no packages of its own, so it ships no hook and every lane
here runs the absent case. A node built from it supplies one — a .NET node runs
`dotnet restore`, a Node node its install — and writes the command in that file
rather than in this document, which is why the command is not listed here.

Three states, three outcomes, and the middle one is the reason the hook is not
just `[ -x … ] && …`:

| `scripts/ci/pre-vendor.sh` | `setup.sh`                                    |
| -------------------------- | --------------------------------------------- |
| absent                     | proceeds — this is a normal, successful setup |
| present, not executable    | refuses, naming the file and the `chmod`      |
| present, exits non-zero    | refuses with the hook's own exit status       |

A hook that cannot run is a misconfiguration, not an absent hook, so it gets its
own refusal. Folding it into the absent case would turn a broken restore into a
silent skip — and a silently skipped restore is the failure the hook exists to
prevent, arriving later wearing the freshness gate's face.

## Local reproduction

Run the same entry point the lane runs. Take the `run:` line from the reusable
workflow you want to reproduce and run it verbatim, for example:

```bash
nix develop .#ci -c ./scripts/ci/pre-commit.sh
```

The Docker and Helm scripts build locally by default. Their reusable workflows set
the documented environment contract to enable publishing.

## Artifact publishing

Docker and Helm callers pass per-repository image or chart values through workflow
`with:` inputs. Empty release versions produce commit builds; CD passes the tag as
the version. Add another image or chart as another caller job rather than putting
repository-specific branching into the reusable workflow.

Release execution runs the real tool: `⚡reusable-release.yaml` enters the
`releaser` shell and calls `scripts/ci/release.sh`, which invokes
`releaser release -c release.yaml`. That script clears `.git/hooks` first,
which is not incidental — the release commit's own message uses a `release:` prefix
that is not a configured commit type, so the commit-msg hook would refuse the
release the tool is in the middle of making.
