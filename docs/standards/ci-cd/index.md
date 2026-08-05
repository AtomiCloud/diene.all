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
calls an existing, executable `scripts/ci` entry point, and that every job obeys
the dependency and cache rules below.

`AtomiCloud/actions.setup-nix` checks out the repository, so do not add an
adjacent `actions/checkout`.

## Action pins

Trusted actions use major pins; every other action uses an exact 40-character SHA
plus its tag in a trailing comment. Which actions are trusted is recorded in
`config/action-trust.json`: each key is an action reference and its value is
`trusted` or `non-trusted`. `scripts/validate/action-pins.sh` reads that file and
fails any action used in a workflow that has no classification, so adding an
action means adding its entry there.

## Every job declares its dependencies

There is one rule, and the caching rules follow from it rather than standing
alongside it:

> **Every `run:` step enters a Nix shell that declares what it needs.**

In practice a `run:` step is exactly one line:

```text
nix develop .#<shell> -c <command>
```

`<shell>` is one of the shells declared in
[`nix/shells.nix`](../../../nix/shells.nix) — today `default`, `ci`, `cd` and
`releaser`. Nothing else is allowed to run: not a bare command, not a shell this
repository does not declare, and not a second command on a following line.

Three things come for free once that holds, and together they are the whole cache
law:

1. **A job's dependencies are visible.** The shell names its tools, so you can see
   what a lane needs without reading the lane.
2. **CI and your laptop run the same tools.** Take the `run:` line out of the
   workflow and paste it into a terminal; that is the whole reproduction recipe.
3. **Every job can reuse the shared Nix store cache** — which is why the cache
   rules below are short.

## Which cache a job carries

Every job falls into exactly one of three cases.

| The job…                                       | Runs on                           | Cache labels       | `NIX_CACHE_EXEMPT_REASON` |
| ---------------------------------------------- | --------------------------------- | ------------------ | ------------------------- |
| runs a script, so it enters a Nix shell        | the cache-capable Namespace venue | both, exactly once | must be absent            |
| runs a script but **must not** share the store | the bare Namespace venue          | none               | **required**, non-empty   |
| runs no script at all — only `uses:` steps     | any permitted runner              | none               | must be absent            |

Reading the rows in words:

- **Cached lanes** are the normal case. They select
  `nscloud-ubuntu-26.04-amd64-16x32-with-cache`, plus `nscloud-cache-size-50gb`
  and the one shared store-cache tag.
- **Isolation lanes** are deliberate. A bare Namespace label cannot attach a cache
  volume at all, so cache absence is part of their contract — and the recorded
  reason is what distinguishes a lane that meant it from a lane that lost its
  cache by accident. Do not create one without writing down why.
- **Action-only jobs** — the merge gatekeeper is the example — run no repository
  script, so there is no Nix store for them to share and no cache for them to be
  exempt from. They may sit on a GitHub-hosted runner.

The cache is **shared, one per OS and architecture**. It is not per platform, per
service or per repository, and the tag deliberately carries no organization name.
Changing the runner OS rotates the tag, which means one cold build before warm
reuse resumes; never alias or carry a 24.04 cache into 26.04.

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

Release execution is wired but not runnable yet: the `releaser` binary is not
published, so nothing here claims a working `releaser`.

## Appendix: the exact declarations the gate accepts

The prose above is the rule. This appendix is the literal text, for when you need
to copy a label or read a refusal.

**Runner labels.** Selection is 26.04-first, and each job selects exactly one venue
label:

| Venue                    | Primary                                       | Fallback                                      |
| ------------------------ | --------------------------------------------- | --------------------------------------------- |
| Namespace, cache-capable | `nscloud-ubuntu-26.04-amd64-16x32-with-cache` | `nscloud-ubuntu-24.04-amd64-16x32-with-cache` |
| Namespace, bare          | `nscloud-ubuntu-26.04-amd64-16x32`            | `nscloud-ubuntu-24.04-amd64-16x32`            |
| GitHub-hosted            | `ubuntu-26.04`                                | `ubuntu-24.04`                                |

Primary and fallback labels are never combined. A job that selects a fallback
records a non-empty job-level `env.NIX_RUNNER_FALLBACK_REASON`; a job on the
primary must not carry that record.

**Cache label pairs.** A cache-capable job carries `nscloud-cache-size-50gb` and
exactly one tag, matching its OS:

```text
nscloud-ubuntu-26.04-amd64-16x32-with-cache
nscloud-cache-tag-nix-store-cache-ubuntu-26.04-amd64

nscloud-ubuntu-24.04-amd64-16x32-with-cache
nscloud-cache-tag-nix-store-cache-ubuntu-24.04-amd64
```

**Marker placement.** `NIX_CACHE_EXEMPT_REASON` and `NIX_RUNNER_FALLBACK_REASON`
are job-level `env:` records. A marker on a step or on the workflow cannot say
which lane it excuses, so it is rejected as misplaced rather than read as a record.

**What the gate refuses.** `scripts/validate/workflows.sh cache-tag-shape` is the
enforcement, and each of its messages names its own fix:

- a `run:` step that is not exactly one `nix develop .#<shell> -c <command>`,
  including one naming a shell absent from `nix/shells.nix`;
- a step-level `uses:` pointing back into this repository — a local composite
  action would carry `run:` steps the gate never sees, so that work belongs in a
  `scripts/ci` entry point instead;
- a job that runs a script on a bare Namespace venue with no exemption recorded;
- an exemption recorded on a cache-capable venue, or on a GitHub-hosted runner;
- a job that runs no script yet claims the shared cache, or records an exemption
  from it;
- a job that runs a script on a GitHub-hosted runner;
- a missing, duplicated, unrotated or organization-scoped cache tag; a missing or
  duplicated cache-size label; cache metadata on a bare or GitHub-hosted venue;
- more than one venue label, an unrecognised label, an unrecorded fallback, or a
  fallback reason recorded on a primary runner.

The gate also refuses to pass vacuously: it fails if no `run:` step, no cached job,
no Namespace job or no GitHub-hosted job was checked at all, and if it cannot read
the shell set out of `nix/shells.nix`.
