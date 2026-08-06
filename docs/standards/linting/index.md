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
  (`${packages.<tool>}/bin/<tool> …`, so the pinned tool runs) or a call to one of
  the four helpers in that file: `validator` and `validators` run one or several
  scripts under `scripts/validate/` with a fixed PATH, and `dlint` and `dlints`
  run one or several `dlint` checks. `dlint` is never routed through the
  `validator` PATH, and the file says why;
- `files` is the regex selecting which paths trigger the hook; a hook with no
  `files` runs on every commit;
- `stages` narrows a hook to a non-default stage; a hook without it runs at the
  default pre-commit stage.

The formatters treefmt drives are the `programs` attribute set in
[`nix/fmt.nix`](../../../nix/fmt.nix); each entry enables one formatter and may
carry its own `excludes`.

**Commit messages are checked.** The `a-releaser-commit` hook runs at the
`commit-msg` stage and calls `releaser lint-commit -c atomi_release.yaml`, so the
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

## The repo-agnostic checks: `dlint`

This repository takes four checks from `dlint`, a tool from the Nix registry,
instead of keeping its own copy of each: `action-pins`, `exec-bits`, `ci-wiring`
and `workflow-policy`. All four replaced repository-local validator scripts.
`workflow-policy` owns the five exact release values after its predecessor was
shown equivalent and retired. The `a-workflows` hook runs `ci-wiring` and
`workflow-policy` unconditionally because they cover independent properties, then
returns the higher exit code so one refusal never hides the other.
`scripts/validate/` still holds checks that are about **this** repository rather
than repositories in general, and now holds only `nixpkgs-pin.sh`. The toolchain
smoke is not among them — `dlint toolchain-smoke` owns it.

Every check reads one file, `dlint.yaml`, resolved from the repository root. Three
things about that file are decisions rather than transcription, and they are
recorded here rather than inside it:

- **`ci-wiring.orchestrators` lists `ci.yaml`, `cd.yaml` and `release.yaml`, and
  deliberately not `🛡️merge-gatekeeper.yml`.** The `⚡`-prefixed workflows are the
  reusable workflows being called, so they are not orchestrators either. The
  gatekeeper is neither: it has no `run:` step, it is the only GitHub-hosted job in
  the tree, and its job calls a third-party action rather than a repository-local
  reusable workflow. `ci-wiring` refuses an orchestrator whose job does not call
  one, so listing it would make the check red for a repository that is correct.
- **No check is disabled and `requireSubjects` is left at its default.** Turning a
  check off is a declaration `dlint` supports — `"exec-bits": false` — and it is
  the honest way to say a check does not apply. It is not a way to make a failing
  check pass, and every check the file declares applies here.
- **An absent section is an error, not a pass.** `dlint` exits `3` when its
  configuration, or a section it needs, or a subject it was told to expect, is
  missing — and `1` only when the repository actually breaks a rule. Any wiring that
  treats `3` as success defeats the tool's whole design, so a hook or CI step must
  pass the exit code through rather than swallow it.

No script asserts the presence and loadability of `dlint.yaml`, and none needs to:
`dlint` refuses to run a check it could not configure, so every invocation asserts
the file. An absent config exits `3` before the check runs, and a config that is
present but unloadable exits `4`. The invocations that carry that assertion here are
the `a-` `dlint` hooks in `nix/pre-commit.nix` — every one of which declares a
`files` filter, so a commit touching none of those paths asserts the config through
no hook at all — and `probes/binary-smoke.ts`, whose
`baseline-binary-smoke-resolves` arm runs `dlint toolchain-smoke` and whose
`baseline-binary-smoke-invokes` arm runs `dlint exec-bits`.

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
