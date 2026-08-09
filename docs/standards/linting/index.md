# Linting

## Running lints

```bash
task lint            # everything, exactly what CI runs
pre-commit run       # the staged files only (what a commit runs)
```

CI runs `pre-commit run --all-files`, so the hook set in `nix/pre-commit.nix` is
the single source of truth: local commits, `task lint`, and CI all execute the
same gates.

## Adding a lint

1. Add a hook to `nix/pre-commit.nix` (one entry: the tool, its files pattern).
2. If the tool comes from the registry or nixpkgs, add it to `nix/packages.nix`.
3. Run `task lint` to see it fire.

- each attribute name is the hook id you pass to `pre-commit run <hook-id>`;
- `name` is the label the run prints;
- `entry` is what actually executes — either a Nix store path
  (`${packages.<tool>}/bin/<tool> …`, so the pinned tool runs) or a call to the
  `validator` helper in that file, which runs one script under `scripts/validate/`
  with a fixed PATH. The `dlint` invocations are written out in full in the
  `a-action-pins-trusted`, `a-action-pins-non-trusted` and `a-workflows` entries
  rather than routed through `validator`, and those entries say why;
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

## The repo-agnostic checks: `dlint action-pins` and `dlint ci-wiring`

`dlint` is a tool from the Nix registry. The parent template runs every check
`dlint.yaml` configures through a single blanket `dlint lint` hook; **this node
deliberately does not take that hook**, because one of the configured checks
contradicts this node — `no-custom-derivations` forbids exactly the `cyanprint`
derivation `nix/packages.nix` builds on purpose. That collision is settled by a
registry hoist, not by deleting the derivation and not by an exemption; see the
comment above `a-enforce-exec` in `nix/pre-commit.nix`.

This repository takes **three** modes, each called explicitly by name:

- `action-pins trusted` and `action-pins non-trusted`, from the two
  `a-action-pins-*` hooks. Trust is one regex, `dlint.yaml`'s
  `checks["action-pins"].trustedPattern`, and there is no trust map to maintain;
- `ci-wiring`, from the `a-workflows` hook: every orchestrator job must resolve to
  a repository-local reusable workflow and every referenced `scripts/ci` entry
  point must exist and be executable. It replaced the `wiring` mode of
  `scripts/validate/workflows.sh`, which is why that script no longer has one.

**The rest of `scripts/validate/` stays, and that is a deliberate difference from
the parent.** The parent template moved four checks to `dlint` — `action-pins`,
`exec-bits`, `ci-wiring` and `workflow-policy` — and deleted the scripts behind
them. Here `action-pins` and `ci-wiring` have moved, and `scripts/validate/action-pins.sh`
went with `action-pins`; `exec-bits` and the release-policy modes have not. Read
`nix/pre-commit.nix` for which mechanism each hook actually runs; do not infer it
from the parent's copy of this page.

`dlint.yaml` in the repository root configures the checks, and two things about
that file are decisions rather than transcription, neither of which can be written
down inside it because the schema carries no place for them:

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
