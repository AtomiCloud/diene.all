---
id: linting
title: Linting
---

# Linting

All repository gates are generated from `nix/pre-commit.nix` and run in the Nix
environment.

## Commands

```bash
task lint
pre-commit run --all-files
nix develop .#ci -c ./scripts/ci/pre-commit.sh
```

The first two commands are the local entry points. CI uses the third so the same
hooks and pinned tools run locally and remotely.

## Reading the hook set

The authoritative hook set is the `hooks` attribute set in
[`nix/pre-commit.nix`](../../../nix/pre-commit.nix). It is not restated here,
because it changes whenever a hook is added or removed. Read it like this:

- each attribute name is the hook id you pass to `pre-commit run <hook-id>`;
- `name` is the label the run prints;
- `entry` is what actually executes — either a Nix store path
  (`${packages.<tool>}/bin/<tool> …`, so the pinned tool runs) or a call to the
  `validator` helper in that file, which runs one script under `scripts/validate/`
  with a fixed PATH. The single `dlint` invocation is written out in full in the
  `a-workflows` entry rather than routed through `validator`, and that entry says
  why;
- `files` is the regex selecting which paths trigger the hook; a hook with no
  `files` runs on every commit;
- `stages` narrows a hook to a non-default stage; a hook without it runs at the
  default pre-commit stage.

The formatters treefmt drives are the `programs` attribute set in
[`nix/fmt.nix`](../../../nix/fmt.nix); each entry enables one formatter and may
carry its own `excludes`.

**Commit messages are checked.** The `a-releaser-commit` hook runs at the
`commit-msg` stage and calls `releaser lint-commit -c release.yaml`, so the
message is measured against the same file that defines the commit types and the
release levels — see
[the conventional-commits standard](../conventional-commits/index.md). There is
still no `.gitlint` hook or file and one must not be added; the vocabulary has one
authority.

This hook was absent for one round, and the reason is worth knowing before you
touch it: no development shell provided the `releaser` binary then, and because
entering a Nix shell reinstalls hooks into the repository's shared git directory,
a commit-msg hook whose binary was missing broke plain `git commit` for every
worktree at once. Its `entry` is an absolute Nix store path rather than a bare
command name, which is what makes it resolve from any worktree and any shell.

## The repo-agnostic check: `dlint ci-wiring`

This repository takes **one** check from `dlint`, a tool from the Nix registry:
`ci-wiring`, which asserts that every orchestrator job resolves to a
repository-local reusable workflow and that every referenced `scripts/ci` entry
point exists and is executable. It replaced the `wiring` mode of
`scripts/validate/workflows.sh`, which is why that script no longer has one.

**The rest of `scripts/validate/` stays, and that is a deliberate difference from
the parent.** The parent template moved four checks to `dlint` — `action-pins`,
`exec-bits` and `ci-wiring` — and deleted the scripts behind the
first three. Only `ci-wiring` has moved here so far. Read `nix/pre-commit.nix` for
which mechanism each hook actually runs; do not infer it from the parent's copy of
this page.

`.dlint.json` in the repository root configures the check, and two things about
that file are decisions rather than transcription, neither of which can be written
down inside it because it is strict JSON with no comments:

- **`ci-wiring.orchestrators` lists `ci.yaml`, `cd.yaml` and `release.yaml`, and
  deliberately not `🛡️merge-gatekeeper.yml`.** The `⚡`-prefixed workflows are the
  reusable workflows being called, so they are not orchestrators either. The
  gatekeeper is neither: it has no `run:` step, it is the only GitHub-hosted job in
  the tree, and its job calls a third-party action rather than a repository-local
  reusable workflow. `ci-wiring` refuses an orchestrator whose job does not call
  one, so listing it would make the check red for a repository that is correct.
- **An absent section is an error, not a pass.** `dlint` exits `3` when its
  configuration, or a section it needs, or a subject it was told to expect, is
  missing — and `1` only when the repository actually breaks a rule. Any wiring that
  treats `3` as success defeats the tool's whole design, so a hook or CI step must
  pass the exit code through rather than swallow it.

The `a-workflows` hook writes `dlint` as an absolute Nix store path,
`${packages.dlint}/bin/dlint`, and that is a safety property rather than a style
rule. A missing package fails at Nix evaluation, loudly, and no shell builds. A
bare `dlint` name would instead fail at runtime with exit `127` — which the probe
helper reports as "could not prove sabotage", so a mutation arm would refuse for
the wrong reason while the baseline arm merely failed.

**Workflow naming is checked here and nowhere upstream.** `.dlint.json` configures
no naming check, so `scripts/validate/workflows.sh workflow-names` — which asserts
`ci.yaml` is named `CI` and `cd.yaml` is named `CD` — has no successor to move to
and is kept on this node. It is nominated for hoist to the parent template so the
check reaches every node instead of this one alone.

## Configuration rules

- Add custom hooks in `nix/pre-commit.nix` with an `a-` prefix.
- Use Nix-provided tool paths or the repository validator wrapper; hooks must not
  depend on host-installed binaries.
- Group one validator script's modes into a single hook rather than one hook per
  mode; hooks are the unit a committer waits on, not the unit of enforcement.
- Give each independent enforcement mechanism its own probe mutation, including
  the mechanisms that share a hook.
- Run a single hook with
  `pre-commit run <hook-id> --all-files` when diagnosing a failure.

`.pre-commit-config.yaml` is generated by Nix and must not be treated as the
source configuration.
