# Validator changes — patch 1

## Removal by ruling, not by staleness

The user ruling of 2026-07-29 deleted hand-written ownership tags from every file,
single-owner and multi-owner alike, and superseded the earlier multi-owner exception
outright. The empirical basis is that the cyanprint resolver never consumed the tags —
it merges on heading boundaries and takes ownership from its own runtime metadata — so
nothing mechanical depended on them.

That ruling **removes the many-owner enforcement**, it does not repair it. The four
artifacts below are gone from this branch:

- `scripts/validate/many-owner.sh` — the validator
- the `a-many-owner` pre-commit hook in `nix/pre-commit.nix`
- `probes/many-owner-schema.ts` — the probe definition
- the `many-owner-schema` row in `probes/features.json`

**This is authorized content removal, not a silenced check.** The distinction is the
whole point of this record, so state it plainly:

- A silenced check is one edited, disabled, or deleted **so that a red result stops
  being reported**. The prohibition on that — never stamp on red — is unchanged and
  still binding on every other check in this repository.
- An authorized removal is one whose **subject no longer exists by ruling**. There are
  no keyed ownership blocks left anywhere in the tree to check, so the validator has no
  subject. Keeping it would assert a contract the ruling abolished.

The ordering matters and is recorded honestly: this validator **was red** before it was
removed, because the tag deletion left it demanding keyed blocks from files that no
longer have any. It is not removed _because_ it was red. It is removed because the
ruling that removed its subject also named it for removal, and it would have been
removed on a green tree by the same authority. Both facts belong in the record.

A previous version of this file argued the opposite disposition — that the validator
should be repaired to treat a marker-free file as legal, and listed the eleven files it
would then have to stop failing. That analysis is **superseded**: it assumed markers
survived somewhere, and under the ruling they do not.

Machine-stamped provenance remains permitted **only** if cyanprint stamps it from its
own metadata. That is a future cyanprint capability and explicitly not this wave, so no
stamping mechanism was added here.

## Hook trim (user ruling, same wave)

The hook set was trimmed in the same pass. Hooks are what a committer waits on, so
several modes of one validator now share one hook; the enforcement mechanisms themselves
are unchanged and each still has its own probe.

### Merged

| Now                | Was                                                               | How                                                    |
| ------------------ | ----------------------------------------------------------------- | ------------------------------------------------------ |
| `a-action-pins`    | `a-action-pins-trusted`, `a-action-pins-non-trusted`              | both modes of `action-pins.sh`, via `validators`       |
| `a-release-config` | `a-release-config`, `a-release-types`                             | `release-config.sh all`, a mode the script already had |
| `a-workflows`      | `a-workflow-wiring`, `a-release-trigger`, `a-release-concurrency` | three modes of `workflows.sh`, via `validators`        |

The `wiring` mode keeps **both halves** unchanged inside the merged hook, per the ruling:
every `scripts/ci` entry point a workflow references exists and is executable, **and**
every orchestrator job resolves to a repository-local reusable workflow that calls one.
Neither half was weakened, reordered, or made conditional.

### Kept split

`a-infisical` and `a-infisical-staged` stay two hooks by explicit ruling, even though
both run the same binary. The full-tree scan and the staged-changes scan answer different
questions and fail for different reasons.

### Dropped

| Hook               | Also removed                                                                             |
| ------------------ | ---------------------------------------------------------------------------------------- |
| `a-cache-tags`     | `scripts/validate/cache-tags.sh`, `probes/cache-tag-shape.ts`, its feature row           |
| `a-helm-docs`      | `probes/hook-helm-docs.ts`, its feature row (the `helm-docs` binary stays)               |
| `a-workflow-names` | the `workflow-names` mode of `workflows.sh`, `probes/workflow-names.ts`, its feature row |

Each drop removes the probe with the hook. `presence-probe-artifacts` requires a probe
definition for every declared feature, so a feature row without its probe file — or the
reverse — would be a genuine red rather than a leftover. All three were **green** when
removed; none was dropped to avoid a failure.

One consequence worth naming: ci.yaml's name is no longer asserted directly, but
`release-trigger` still requires `.on.workflow_run.workflows == ["CI"]`, so a rename of
ci.yaml is still caught — one hop later, by the release trigger check rather than by a
dedicated name check.

## Resulting hook set

Twelve hooks declared, down from twenty — eleven at the pre-commit stage plus the
commit-msg hook. `nix/pre-commit.nix` remains the authoritative statement of the set; it
is not restated here, because it changes whenever a hook is added or removed.
`docs/standards/linting/index.md` explains how to read it.

## Upstream classification

Every region touched by this record's work is `workspace`-owned: the trimmed hooks sit
in the workspace block of `nix/pre-commit.nix`, all four removed feature rows carry
`"template": "diene/workspace"`, and every removed script and probe was born on this
branch. No part of it lands in a chain-root-owned region, so it owes no
`UPSTREAM-CHANGES.md` entry. The touched files still appear in that audit's
classification table as changed files.
