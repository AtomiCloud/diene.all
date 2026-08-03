# Upstream change records

Produced by the upstream adoption test: ownership decides where a fix lands.
`source: main` blocks and chain-root-born files are upstream — the needed change is
recorded here rather than forked locally. `source: workspace` content is fixed in place
and is deliberately **not** recorded here.

This file is a mandatory audit artifact and is written even when nothing is owed.

## Audit scope and classification

Ownership was resolved per region, not per file: at audit time an explicit
`source: <owner>` ownership marker decided the block it headed, and only unmarked files
fell back to the birth trace `git log --follow --diff-filter=A -- <path>`. (The
hand-written ownership markers themselves were deleted later in this same wave under the
user's 2026-07-29 ruling — see "Ownership-tag removal" below; ownership now lives in
cyanprint's runtime metadata.) Files born at `24105ef`
("materialize atomi/nix sample (yes_basic_yes_llm) as chain root") are upstream; files
born at `f74cf31` ("materialize workspace spine baseline") or later on this line are
owned here.

### Files changed by this patch

| File                                           | Classification                                                                                                            |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `.coderabbit.yaml`                             | owned-here                                                                                                                |
| `.dockerignore`                                | owned-here                                                                                                                |
| `.github/actionlint.yaml`                      | owned-here                                                                                                                |
| `.github/dependabot.yml`                       | owned-here                                                                                                                |
| `.github/workflows/cd.yaml`                    | owned-here                                                                                                                |
| `.github/workflows/ci.yaml`                    | owned-here                                                                                                                |
| `.github/workflows/release.yaml`               | owned-here                                                                                                                |
| `.github/workflows/⚡reusable-docker.yaml`     | owned-here                                                                                                                |
| `.github/workflows/⚡reusable-helm.yaml`       | owned-here                                                                                                                |
| `.github/workflows/⚡reusable-precommit.yaml`  | owned-here                                                                                                                |
| `.github/workflows/⚡reusable-release.yaml`    | owned-here                                                                                                                |
| `.github/workflows/🛡️merge-gatekeeper.yml`     | owned-here                                                                                                                |
| `.gitignore`                                   | mixed regions; ownership-tag removal only (wave ruling)                                                                   |
| `.prettierrc.yaml`                             | owned-here                                                                                                                |
| `CLAUDE.md`                                    | mixed regions; ownership-tag removal, plus one superseded keyed-block sentence dropped in its `workspace` region          |
| `README.md`                                    | upstream file, change confined to its `workspace` block; ownership tags removed (wave ruling)                             |
| `Taskfile.yaml`                                | owned-here                                                                                                                |
| `atomi_release.yaml`                           | owned-here                                                                                                                |
| `docs/domain/README.md`                        | owned-here                                                                                                                |
| `docs/standards/ci-cd/index.md`                | owned-here                                                                                                                |
| `docs/standards/conventional-commits/index.md` | owned-here                                                                                                                |
| `docs/standards/docker/index.md`               | owned-here                                                                                                                |
| `docs/standards/helm/index.md`                 | owned-here                                                                                                                |
| `docs/standards/infisical/index.md`            | owned-here                                                                                                                |
| `docs/standards/linting/index.md`              | owned-here                                                                                                                |
| `docs/standards/semantic-release/index.md`     | owned-here                                                                                                                |
| `docs/standards/service-tree/index.md`         | owned-here                                                                                                                |
| `docs/standards/shell-scripts/index.md`        | owned-here                                                                                                                |
| `docs/standards/taskfile/index.md`             | owned-here; one superseded keyed-block sentence reworded in the fold                                                      |
| `flake.nix`                                    | upstream file, change confined to its `workspace` block                                                                   |
| `infra/Dockerfile`                             | owned-here                                                                                                                |
| `infra/root_chart/Chart.yaml`                  | owned-here                                                                                                                |
| `infra/root_chart/README.md`                   | owned-here (generated by `helm-docs`)                                                                                     |
| `infra/root_chart/README.md.gotmpl`            | owned-here (new in this patch)                                                                                            |
| `infra/root_chart/templates/configmap.yaml`    | owned-here                                                                                                                |
| `infra/root_chart/values.yaml`                 | owned-here                                                                                                                |
| `nix/env.nix`                                  | upstream file, changes confined to `workspace` blocks; ownership tags removed (wave ruling)                               |
| `nix/fmt.nix`                                  | upstream file, change confined to its `workspace` block                                                                   |
| `nix/packages.nix`                             | upstream file, change confined to the `workspace` block; ownership tags removed (wave ruling)                             |
| `nix/pre-commit.nix`                           | upstream file, changes confined to workspace-born regions; ownership tags removed (wave ruling) and the hook trim applied |
| `nix/shells.nix`                               | mixed regions; ownership-tag removal only (wave ruling)                                                                   |
| `probes/cache-tag-shape.ts`                    | owned-here; **removed** with the `a-cache-tags` hook (hook trim)                                                          |
| `probes/features.json`                         | upstream file, changes confined to `diene/workspace`-templated rows; the `atomi/nix` rows are byte-identical              |
| `probes/hook-helm-docs.ts`                     | owned-here; **removed** with the `a-helm-docs` hook (hook trim)                                                           |
| `probes/lib/README.md`                         | owned-here                                                                                                                |
| `probes/many-owner-schema.ts`                  | owned-here; **removed** with the ownership-block enforcement (removal by ruling)                                          |
| `probes/workflow-names.ts`                     | owned-here; **removed** with the `a-workflow-names` hook (hook trim)                                                      |
| `scripts/ci/setup.sh`                          | mixed regions; ownership-tag removal only (wave ruling)                                                                   |
| `scripts/local/skills-sync.sh`                 | mixed regions; ownership-tag removal only (wave ruling)                                                                   |
| `scripts/validate/binary-smoke.sh`             | owned-here                                                                                                                |
| `scripts/validate/cache-tags.sh`               | owned-here; **removed** with the `a-cache-tags` hook (hook trim)                                                          |
| `scripts/validate/many-owner.sh`               | owned-here; **removed** with the ownership-block enforcement (removal by ruling)                                          |
| `scripts/validate/workflows.sh`                | owned-here; the dropped `workflow-names` mode removed, the other three modes unchanged                                    |
| `tasks/Taskfile.docker.yaml`                   | owned-here                                                                                                                |
| `tasks/Taskfile.helm.yaml`                     | owned-here                                                                                                                |
| `tasks/Taskfile.secret.yaml`                   | owned-here                                                                                                                |
| `UPSTREAM-CHANGES.md`                          | owned-here (this audit artifact, updated by the fold)                                                                     |
| `VALIDATOR-CHANGES.md`                         | owned-here (new in this patch)                                                                                            |

Region notes for the mixed files:

- `README.md` — the `nix-root` block is `source: main` and was left alone; the rewritten
  Commands and Standards sections sit in the `workspace` block.
- `nix/packages.nix` — `atomipkgs` and `nix-unstable` are `source: main` and were left
  alone; the package removals are all in the `workspace` (`nix-2605`) block.
- `nix/env.nix` — `system` is `source: main` and was left alone; `dev`, `lint` and `main`
  are `source: workspace`.
- `nix/pre-commit.nix` — the `nix-root-format` block (the `treefmt` hook) is
  `source: main` and was left alone. The `validator-runtime`/`validator` `let` block
  carries no marker, so its ownership was resolved by region birth trace:
  `git log -S validator-runtime -- nix/pre-commit.nix` gives `f74cf31`, the workspace
  spine baseline, so it is owned here and was repointed in place. The `a-helm-lint` hook
  sits inside the `workspace-hooks` block.
- `flake.nix` and `nix/fmt.nix` — chain-root-born files whose only marked block was
  `source: workspace`; stripping that marker is a workspace-owned change.

### Ownership-tag removal (Rule 1 × Rule 5, ratified 2026-07-29)

The fold on top of this patch deleted every remaining hand-written ownership tag — the
`### <key>` line and its source-marker partner, deleted as adjacent pairs — across the
workspace, single-owner and multi-owner alike, under the user's 2026-07-29 ruling that
supersedes the multi-owner exception. Ownership lives in cyanprint's runtime metadata;
files carry no hand-written provenance.

Per the ratified interaction ruling (both leads concurring): deleting an ownership
marker — including one that attributed its block to `main` — is **not** an upstream
content change. Markers carried no upstream contract (nothing mechanical ever consumed
them), and Rule 5 governs content regions, which a marker is not. **No per-marker
records appear in this file — deliberately.** The touched files still appear in the
classification table above (they must: bytes changed), each carrying the standard note
that the only change in any main-owned region was tag removal under this wave ruling.

Files touched by the tag-removal fold: `.gitignore`, `CLAUDE.md`, `README.md`,
`nix/env.nix`, `nix/packages.nix`, `nix/pre-commit.nix`, `nix/shells.nix`,
`scripts/ci/setup.sh`, `scripts/local/skills-sync.sh` (tag pairs), plus
`docs/standards/taskfile/index.md` and `CLAUDE.md` (one superseded keyed-block doctrine
sentence each) and this audit artifact itself.

### Enforcement removal and hook trim (same wave ruling)

The same fold removed the ownership-block enforcement outright and applied the user-final
hook trim. **Nothing is owed upstream for either, and the absence of records here is a
verified result rather than an omission:**

- every removed validator and probe is workspace-born at `f74cf31`, so no upstream file
  was deleted;
- the trimmed and merged hooks all sit in the `workspace-hooks` region of
  `nix/pre-commit.nix`; the `treefmt` hook, the one `source: main` region in that file,
  was not touched;
- `probes/features.json` is chain-root-born and therefore upstream, but all four removed
  rows carry `"template": "diene/workspace"`, and its `atomi/nix` rows are byte-identical
  before and after (verified by comparing the filtered sets, not by reading the diff).

All twelve files involved appear in the classification table above, including the six
that were deleted. What was removed, and why it is authorized content removal rather than
a silenced check, is recorded in `VALIDATOR-CHANGES.md` — the artifact the ruling named
for it. That record is not restated here.

### Files changed by the shared payload

The agnostic standards payload lands on top of the fold above. Fifty-five of its sixty
paths are new files born on this line, so the birth trace makes them owned-here and they
owe nothing upstream: the twelve thin skill triggers under `.claude/skills/`,
`.markdownlint-cli2.jsonc` and `.markdownlint.json`, thirty-six documents under
`docs/standards/` (the twelve standard indexes, the contributor-docs reference set, and
the reserved C0 slot at `docs/standards/contracts/README.md`, which carries no C0
contract content), and five probe definitions under `probes/`. The five paths that
already existed are classified individually:

| File                   | Classification                                                                                                                                                                                             |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CLAUDE.md`            | upstream file; the shared index sections and the placement sentence are new content — no pre-existing region was rewritten                                                                                 |
| `README.md`            | upstream file, addition confined to the workspace-born Standards section                                                                                                                                   |
| `nix/pre-commit.nix`   | upstream file; the two new hooks are shared-born entries in the hooks set, and the `treefmt` hook — the one `source: main` region in that file — was not touched                                           |
| `probes/features.json` | upstream file; the five appended rows all carry `"template": "diene/shared"`, and the `atomi/nix` and `diene/workspace` rows are byte-identical before and after (verified by comparing the filtered sets) |
| `UPSTREAM-CHANGES.md`  | owned-here (this audit artifact, updated by the payload)                                                                                                                                                   |

**Nothing is owed upstream for this payload, and the absence of records below is a
verified result rather than an omission:**

- the new `a-markdownlint` hook selects by directory shape rather than by topic name, so
  it also lints the eleven parent-owned standards under `docs/standards/` and the eleven
  parent-owned skill triggers. They pass unchanged; no parent document was edited to make
  the gate green.
- the one collision found was mechanical rather than editorial. Markdownlint counts a YAML
  frontmatter `title:` as a top-level heading, so every parent standard carrying
  frontmatter plus an `#` heading tripped MD025. It is resolved in the shared-owned
  `.markdownlint.json` with `"MD025": { "front_matter_title": "" }`, which leaves the rule
  enforcing one `#` heading per document. No upstream file changed, so no record is owed.

### Documentation files audited but not changed

Every document in the repository was swept, not only the ones changed:

| File                                   | Classification | Finding                                                                                                                                                                                                                                                                           |
| -------------------------------------- | -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `docs/standards/nix/index.md`          | **upstream**   | **NOT compliant — three upstream-owned defects recorded below (records 2, 3 and 4):** a dangling pointer, a module/topology inventory, and two tool-output tables. Its process guidance and its deferral to `flake.nix` for registries and wiring are compliant; the rest is not. |
| `CLAUDE.md`                            | mixed          | Compliant — an index of resolvable pointers, one per surface. Later changed by the tag-removal fold (see the classification table above).                                                                                                                                         |
| `Changelog.md`                         | owned-here     | Compliant — states the release pipeline generates it; no restated content.                                                                                                                                                                                                        |
| `docs/developer/CommitConventions.md`  | owned-here     | Compliant — points at `releaser conventions` and `atomi_release.yaml` as the machine-readable truth.                                                                                                                                                                              |
| `.claude/skills/nix/SKILL.md`          | **upstream**   | Compliant — a single resolvable pointer to its standard. Chain-root-born at `24105ef`, unlike the other ten skill files; classified separately because a grouped row would make this audit false.                                                                                 |
| `.claude/skills/*/SKILL.md` (other 10) | owned-here     | Compliant — each is a single resolvable pointer to its standard, with no duplicated content. All ten trace to `f74cf31`.                                                                                                                                                          |
| `probes/lib/README.md`                 | owned-here     | Changed (see above).                                                                                                                                                                                                                                                              |

`.claude/skills/vendor/` was excluded from the sweep: it is a vendored tree that this
repository must never hand-edit.

## Records

### 1. Rule-text placement for the bundle-check rule belongs in the upstream nix standard

- **File:** `docs/standards/nix/index.md` (chain-root-born at `24105ef`, upstream-owned).
- **What:** the bundle-check rule ("never declare a binary an imported bundle already
  ships; verification is build-only via
  `ls "$(nix build --no-link --print-out-paths .#<bundle>)/bin"`; cannot build → remove
  nothing and record candidates") should be stated in this standard, most naturally in
  its "Adding a Package" and "Removing a Package" operations, which currently describe
  the mechanical edit without the bundle check.
- **Why:** the rule's own placement ruling puts it in the nix standard at the meta layer.
  This repository's copy of that standard is upstream-owned, and there is no
  template-specific reason the upstream source would refuse the guidance — it applies to
  every project built from this chain root, not just to the workspace. Adding the text to
  the local copy would fork upstream content, so it is recorded here instead.
- **Not blocking:** the rule was still _applied_ to this node's content in this patch —
  see the removals recorded under the bundle check below. Only the documentation of the
  rule is owed upstream.

### 2. Dangling pointer to a file that does not exist

- **File/region:** `docs/standards/nix/index.md:342` (chain-root-born at `24105ef`,
  upstream-owned; the bullet carries no marker, so ownership follows the file's birth).
- **What:** the "Reference" bullet names `.claude/skills/nix/reference.md`:

  ```
  - **Reference**: `.claude/skills/nix/reference.md` - File patterns and examples
  ```

  That path does not exist. `git ls-files .claude/skills/nix/` returns exactly one file,
  `.claude/skills/nix/SKILL.md`, and the directory on disk contains only that file.
  Upstream should either
  delete the bullet or publish the missing `reference.md`.

- **Why:** Rule 2 requires every pointer to resolve to a path that exists at the moment it
  is written; a pointer at a missing path is worse than the duplication it replaced. The
  adjacent `.claude/skills/nix/SKILL.md` bullet on line 341 resolves and is fine. There is no
  template-specific reason upstream would refuse this, so it belongs upstream rather than
  being patched locally.

### 3. Module and topology inventory duplicated from the flake wiring

- **File/region:** `docs/standards/nix/index.md` — `## Quick Reference` (the `nix/` file
  tree, lines 11–21), the per-module `## File Structure` sections (lines 23–114),
  `## Data Flow` (the registries→packages→env→shells→flake diagram, lines 118–128), and
  the per-file responsibility list under `## Key Concepts` → `### Modularity`
  (lines 305–312).
- **What:** each of these restates the current module topology — which files exist under
  `nix/`, what each one is for, and how they feed each other. They should become a pointer
  to the wiring itself plus how to read it, keeping only the genuinely process-level
  guidance such as the `inherit shellHook;` requirement. The truth that exists today and
  can be pointed at: enumerate the modules with `rg --files nix`; read `flake.nix` for how
  each module is imported and which parameters it receives, which is what establishes the
  registries→packages→env→shells→flake ordering; and read each module's own argument set
  and top-level attribute names for what it actually provides (`nix/env.nix` takes
  `{ pkgs, packages }` and returns the named groups, `nix/shells.nix` takes `env` and
  returns the named shells, and so on).
  **Do not** direct readers to per-module head comments describing each module's role:
  none of `nix/env.nix`, `nix/fmt.nix`, `nix/packages.nix`, `nix/pre-commit.nix` or
  `nix/shells.nix` carries one — each begins directly with its Nix argument set. If
  upstream prefers that shape, adding those comments has to be part of this same upstream
  change, not a pointer written before they exist.
- **Why:** the operative Rule 2 test is whether the content must change when a config file
  changes. Adding, removing or renaming a file under `nix/`, or rewiring which module
  consumes which, falsifies all four sections at once — so they are an INVENTORY, not
  process. Chain-root-born, so Rule 5 requires recording rather than editing in place.
- **Note:** the sections that already say "Read `flake.nix` to see the exact inputs and
  wiring" and "To find what registries and variable names are available: Read `flake.nix`"
  are the correct pattern and should be kept; this record is about the surrounding
  restatement, not those lines.

### 4. Two tables that restate tool output

- **File/region:** `docs/standards/nix/index.md` — the hook-types table (lines 85–89) and
  the `## Usage Commands` table (lines 292–299).
- **What:** the usage-commands table lists `nix develop`, `nix develop .#name`,
  `nix flake update`, `nix search nixpkgs name`, `nix flake show` and `direnv reload`. That
  is the Nix and direnv CLI surface, owned by those tools' own help output, and it goes
  stale silently when a command, flag or spelling changes upstream in Nix. It should point
  at `nix --help` / `nix <subcommand> --help` and `direnv --help` and teach which
  subcommands matter here, rather than mirroring them. The hook-types table
  (Formatter / Linter / Enforcer with `eslint, shellcheck` as examples) names tools this
  repository does not necessarily configure and duplicates what the `hooks` attribute set
  in `nix/pre-commit.nix` already shows; it should point there instead.
- **Why:** Rule 2's test again — both change when tool output or configuration changes,
  neither changes only when the team changes how it works. Chain-root-born, so recorded
  rather than fixed locally.
- **Completeness note:** recorded here deliberately. The user's own backtest verdict on
  this rule — external review-session evidence, not a file in this repository — observes
  that of the four passing models, none recorded
  these two tables — "the record is correct in all four and _complete_ in none". This
  audit records them so the upstream doc's full Rule 2 debt is visible in one place.

## Bundle check — what was verified and removed

Recorded here for provenance because it is the evidence behind the `nix/packages.nix`
change, even though the change itself is workspace-owned and was fixed in place.

Verification was build-only, run in this environment:

```bash
ls "$(nix build --no-link --print-out-paths .#atomiutils)/bin"
ls "$(nix build --no-link --print-out-paths .#infrautils)/bin"
ls "$(nix build --no-link --print-out-paths .#infralint)/bin"
```

- `atomiutils` ships `bash`, `jq`, `yq`, `awk`/`gawk`, `sed`, `grep`, `find`, the
  coreutils set, `curl`, `tar` and `gomplate`.
- `infrautils` ships `docker`, `dockerd`, `helm`, `k3d`, `kubectl`, `kubectx`, `kubens`,
  `tofu`, `garden`, `tilt` and `mirrord`.
- `infralint` ships `hadolint`, `helm-docs`, `helmlint`, `terraform-docs`, `tflint` and
  `tfsec`.

Removed from the `workspace` block of `nix/packages.nix` because a bundle already ships
them: `bash`, `jq`, `yq-go` (atomiutils); `docker-client`, `kubernetes-helm`
(infrautils). Removed from the matching `dev`, `lint` and `main` groups in `nix/env.nix`.
Every shell composes `system` (`atomiutils` + `infrautils`), so all four shells still
resolve these tools.

Kept, because no imported bundle ships them: `actionlint`, `git`, `go-task`, `infisical`,
`kubeconform`, `kyverno`, `pre-commit`, `ripgrep`, `shellcheck`, `skopeo`, `treefmt`.

No removal was blocked and nothing had to be recorded in place of a removal: the two
references to the removed packages were repointed successfully in workspace-owned regions
(`validator-runtime` and `validator` to `packages.atomiutils`; `a-helm-lint` to
`packages.infrautils`), and `nix develop .#ci -c pre-commit run --all-files` then passed
all 14 pre-commit hook IDs (17 expanded checks), so no failure output needed recording.

## Open items deliberately not recorded

- The point-at-truth rule's documentation home is **pending the user's ruling**. The rule
  was applied to this node's content; no home was invented for its text, here or
  anywhere else.
- ~~The Shared deletions (contributor docs, lychee) are pending user confirmation and are
  out of scope for this node.~~ **Resolved.** Both landed on this node with the shared
  payload: the contributor-docs standard is at `docs/standards/contributor-docs/`, and
  lychee backs the `a-claude-links` hook in `nix/pre-commit.nix`. Neither is pending and
  neither is out of scope any more, so this is no longer an open item.

---

# dart-lib generation 21 — accepted-parent adoption audit (2026-08-03)

Everything above this heading is the **inherited historical record**, carried into this
candidate byte-for-byte from the accepted parent. It is not edited, reinterpreted, or
superseded here. Everything below is the **dart-lib generation 21** audit and speaks only
for this node.

**Three lead decisions landed on 2026-08-03 while this audit was open**, and all three are
applied in place at the records they govern rather than only noted here:

1. **G21-7**'s bypass form — blanket `--no-verify` → the named skip
   `SKIP=a-infisical,a-infisical-staged` (G21.4).
2. **G21-7 withdrawn as a defect** — a sandbox lifecycle trace showed no hook is installed at the
   fixture commit, so the skip is redundant and the parent has nothing to repair. The defect
   count in G21.4 is **six**, not seven (G21.4).
3. **N-1**'s disposition — root `Changelog.md` stays byte-identical; upstream debt only, no
   node-local edit (G21.5).

## G21.0 Scope, anchors, and method

| Anchor          | Revision                                   | Role                                                                |
| --------------- | ------------------------------------------ | ------------------------------------------------------------------- |
| Accepted parent | `1ad2579703f20e419fa62c414cb6e4bf3eaac208` | `shared-wo-docker-helm` g3 head; the ownership baseline (161 files) |
| Prior node head | `09759caecf02427509043940857a522ea26ca084` | the dart-lib line before this adoption                              |
| Merge base      | `e01fe368b9fe30bee238c809a58444c9170998f2` | common ancestor of the two                                          |
| Candidate       | the working tree at audit time             | `MERGE_HEAD` is the accepted parent; the merge is not yet committed |

**Ownership rule used here.** The accepted parent is the upstream for this node: every byte
present at `1ad2579` is **parent-owned** unless this node replaced it. Content born on the
dart-lib line — the Dart package, the Dart probes/scripts/workflows, and the
`"template": "diene/dart-lib"` feature rows — is **node-owned**. Files that carry both are
classified by region, never whole-file. Hand-written ownership markers no longer exist at
either anchor (see G21.3), so Rule 5's marker fallback had nothing to read. Every path in
this audit was decided by a stronger and directly checkable test — presence and exact bytes
at `1ad2579`, compared with `git diff --name-status` and `git diff --numstat` — so Rule 5's
birth trace `git log --follow --diff-filter=A -- <path>` was not needed and was not run for
any path here. No path in the population was left unresolved by the byte comparison.

**Time basis.** Every count below is a measurement of the candidate working tree on
2026-08-03 with the merge staged and uncommitted. It drifts as the tree changes; recompute
with the commands in G21.6 rather than trusting the numbers if the tree has moved. This
file is append-only, so no hash or line count is pinned for it.

## G21.1 Classification — every path changed against the accepted parent

Population: `git diff --name-only 1ad2579703f20e419fa62c414cb6e4bf3eaac208 --` after this
edit returns **103** paths — `--name-status` reports **78** added, **25** modified and **0**
deleted. This artifact is one of the 25: it exists at the accepted parent, so appending to it
registers as a modification, not an addition. The 24 other modified paths are the
parent-shape files classified in G21.1b and G21.1c.
Nothing was deleted relative to the accepted parent: the five validator/probe
files retired by the inherited wave ruling (`probes/cache-tag-shape.ts`,
`probes/many-owner-schema.ts`, `probes/workflow-names.ts`, `scripts/validate/cache-tags.sh`,
`scripts/validate/many-owner.sh`) are already absent at the accepted parent and absent here,
so they produce no row.

### G21.1a Node-born additions — 78 paths, none present at the accepted parent

Every path in this section is node-owned: it does not exist at `1ad2579`, so it can carry no
parent-owned region and owes nothing upstream. Grouped rows below are exhaustive
enumerations, not summaries; each group's members are listed and every member shares the
single stated classification.

| #   | Group                            | Count | Members                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | Classification                                                                  |
| --- | -------------------------------- | ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| 1   | Publishable package              | 23    | `packages/diene_dart_lib/` × `.pubignore`, `CHANGELOG.md`, `LICENSE`, `README.md`, `analysis_options.yaml`, `doc/diene_dart_lib.md`, `example/diene_dart_lib_example.dart`, `lib/diene_dart_lib.dart`, `lib/src/note.dart`, `lib/src/note_summary.dart`, `lib/test_helper.dart`, `pubspec.yaml`, `skills/diene-dart-lib-usage/SKILL.md`, `skills/diene-dart-lib-usage/patterns.md`, `test/conformance/c0_conformance_test.dart`, `test/fixtures/c0/manifest.json`, `test/fixtures/c0/note_basic.json`, `test/fixtures/c0/note_empty_body.json`, `test/fixtures/c0/note_unicode.json`, `test/meta/note_assertions_test.dart`, `test/unit/note_summary_test.dart`, `test/unit/note_test.dart`, `tool/deadcode_entrypoints.dart`                                                                            | node-owned (new Dart sample package)                                            |
| 2   | Dart CI/CD workflow callees      | 7     | `.github/workflows/` × `cd.yaml`, `⚡reusable-analyze.yaml`, `⚡reusable-deadcode.yaml`, `⚡reusable-nix-check.yaml`, `⚡reusable-package-validate.yaml`, `⚡reusable-publish.yaml`, `⚡reusable-test.yaml`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | node-owned                                                                      |
| 3   | Root Dart/tooling config         | 4     | `.gitlint`, `analysis_options.yaml`, `codecov.yml`, `pubspec.yaml`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | node-owned                                                                      |
| 4   | Probe definitions + harness test | 28    | the 27 `diene/dart-lib` probe files (`automated-publishing-credential-policy`, `c0-fixture-harness`, `codecov-configuration`, `conditional-meta-activation`, `dart-analyze`, `dart-format`, `dart-tool-inventory`, `deadcode-production-only`, `deadcode-whole-package`, `package-validate-workflow-wiring`, `pana-score`, `probe-inventory`, `pub-workspace-metadata-validator`, `pub-workspace-resolution`, `publish-archive-contents`, `publish-command-policy`, `publish-dry-run`, `publish-tag-policy`, `publish-version-guard`, `publish-workflow-wiring`, `release-policy-values`, `sample-execution-consumption`, `testhelper-meta-contract`, `testhelper-meta-coverage-ledger`, `unit-coverage-ledger`, `unit-tests`, `usage-skill`, each `probes/<name>.ts`) plus `probes/lib/helpers.test.ts` | node-owned                                                                      |
| 5   | Dart scripts                     | 13    | `scripts/ci/` × `analyze.sh`, `deadcode.sh`, `nix-check.sh`, `package-validate.sh`, `publish.sh`, `test-all.sh`, `test.sh`; `scripts/local/` × `deadcode.sh`, `watch-tests.sh`; `scripts/release/format-changelog.sh`; `scripts/validate/` × `dart-package.sh`, `publish-version.sh`, `release-policy.sh`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | node-owned                                                                      |
| 6   | Test taskfile                    | 1     | `tasks/Taskfile.test.yaml`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | node-owned                                                                      |
| 7   | Vendored skills                  | 2     | `.claude/skills/vendor/diene_dart_lib/diene-dart-lib-usage/SKILL.md`, `.../patterns.md`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | **vendored, machine-generated** — not hand-edited; see the vendoring note below |

Group total: 23 + 7 + 4 + 28 + 13 + 1 + 2 = **78**.

**Vendoring note (group 7).** `.claude/skills/vendor/**` is generated by
`scripts/local/skills-sync.sh` from the shipped package skills and must never be hand-edited.
Both vendored files are byte-identical to their generators at
`packages/diene_dart_lib/skills/diene-dart-lib-usage/` (verified with `diff -r`, no
differences), and `.claude/skills/vendor/manifest.json` (classified in G21.1c) is the synchronizer's
own manifest, not authored content. `.claude/skills/vendor/.gitkeep` is unchanged.

### G21.1b Parent-shape files changed by pure addition — 12 paths, zero parent lines removed

For each of these, `git diff --numstat 1ad2579 --` reports **0** deletions: every
accepted-parent byte survives unchanged and the node's content is appended or inserted
alongside it.

| File                                   | +lines | Node-owned region added                                                                                                                       | Parent-owned region                                   |
| -------------------------------------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| `.github/dependabot.yml`               | 4      | a `pub` ecosystem entry for `/packages/diene_dart_lib`                                                                                        | unchanged                                             |
| `.github/workflows/ci.yaml`            | 46     | six job blocks (`analyze`, `unit`, `meta`, `deadcode`, `package-validate`, `nix-check`) calling the node's reusable workflows                 | the `precommit` job is unchanged                      |
| `.gitignore`                           | 9      | `.probe-evidence/` and the Dart artifact block (`.dart_tool/`, `.packages`, `.pub-cache/`, `build/`, `coverage/`, `doc/api/`, `pubspec.lock`) | unchanged                                             |
| `Taskfile.yaml`                        | 71     | the `unit`/`meta` includes and eleven Dart tasks                                                                                              | `secret` include and `setup`/`skills` tasks unchanged |
| `config/action-trust.json`             | 2      | `actions/upload-artifact` and `codecov/codecov-action` marked trusted for the node's CI                                                       | unchanged                                             |
| `nix/env.nix`                          | 3      | `dart` in `dev` and `main`, `gitlint` in `lint`                                                                                               | unchanged                                             |
| `probes/features.json`                 | 135    | 27 appended rows, all `"template": "diene/dart-lib"`                                                                                          | see the row-set proof below                           |
| `probes/lib/helpers.ts`                | 27     | `preserveMutationBeforeRestore`, exported alongside the existing helpers                                                                      | unchanged — but see record **G21-8**                  |
| `probes/skills-freshness.ts`           | 51     | an offline `dart pub get` in `setup.post`, three Dart clean targets, and the independent-Pub-oracle mutation                                  | unchanged                                             |
| `probes/skills-sync.ts`                | 43     | an offline `dart pub get` in `setup.post`, the `.probe` clean target, and the hosted-Pub baseline                                             | unchanged                                             |
| `scripts/ci/setup.sh`                  | 6      | `dart pub get` before skills synchronization                                                                                                  | unchanged — but see record **G21-5**                  |
| `scripts/validate/skills-freshness.sh` | 147    | the independent Dart oracle (tracked-pubspec derivation, `package_config.json` inventory, per-package vendor assertion)                       | unchanged                                             |

**`probes/features.json` row-set proof.** The accepted parent has 39 rows
(7 `atomi/nix`, 27 `diene/workspace`, 5 `diene/shared`); the candidate has 66. The 39
parent rows are byte-identical **and in the same order** — verified by comparing the
sorted-key JSON of the parent file against the candidate's first 39 rows, and separately by
comparing the parent file against the candidate filtered to `template != "diene/dart-lib"`.
Both comparisons are empty. The 27 appended rows are 20 gates, 4 smokes, 3 presence, all
`diene/dart-lib`.

### G21.1c Parent-shape files where accepted-parent bytes were replaced — 12 paths

These are the only places where parent bytes did not survive. Each is reconciled exactly;
the ones that replace generic parent content carry an upstream record in G21.4.

| File                                   | −lines | Exactly what was replaced                                                                                                                                                                                                                              | Classification                                                                                                                                  |
| -------------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `.claude/skills/vendor/manifest.json`  | 1      | the empty `[]` manifest → the two vendored dart-lib skill paths                                                                                                                                                                                        | **vendored, machine-generated** by `scripts/local/skills-sync.sh`; not hand-edited                                                              |
| `atomi_release.yaml`                   | 3      | `changelogFile: Changelog.md` → `packages/diene_dart_lib/CHANGELOG.md` (plus a `changelogTitle`); `prepareCmd` gains `format-changelog.sh`; the `Changelog.md` asset → `packages/diene_dart_lib/CHANGELOG.md` + `packages/diene_dart_lib/pubspec.yaml` | node-owned: per-node release identity, which every child retokenizes. See finding **N-1**                                                       |
| `flake.nix`                            | 2      | `shellHook = checks.pre-commit-check.shellHook` → `pre-commit.shellHook`; `pre-commit-check = pre-commit` → `pre-commit-offline`                                                                                                                       | node-caused re-point of parent wiring; the generic knob is offered upstream in **G21-9**                                                        |
| `nix/packages.nix`                     | 1      | the final composition line gains `// dart-lib-packages // dart-lib-tools`                                                                                                                                                                              | node-owned: the minimum wiring edit that admits the node's two new attrsets; the parent attrsets are untouched                                  |
| `nix/pre-commit.nix`                   | 1      | the `a-releaser-commit` entry `releaser lint-commit -c atomi_release.yaml` → `${packages.gitlint}/bin/gitlint --staged --msg-filename`                                                                                                                 | parent-owned region replaced — upstream defect **G21-1**; the `offline ? false` parameter and four `a-dart-*` hooks are additive and node-owned |
| `probes/hook-infisical-full.ts`        | 1      | the fixture-seeding commit gains the named skip `SKIP=a-infisical,a-infisical-staged`                                                                                                                                                                  | parent-owned region replaced — **G21-7, withdrawn as a defect**: a harmless redundant skip, nothing owed upstream as a repair                   |
| `probes/hook-shellcheck.ts`            | 5      | the mutation body wrapped in `try`/`finally` with `preserveMutationBeforeRestore`; `expectedImpact: []` → `['release-policy-values']`                                                                                                                  | mixed: the `expectedImpact` value is node-caused (the node added that probe row); the `try`/`finally` hardening is upstream defect **G21-6**    |
| `probes/release-type-vocabulary.ts`    | 8      | same shape as above, on `atomi_release.yaml`                                                                                                                                                                                                           | mixed, as above — upstream defect **G21-6**                                                                                                     |
| `probes/releaser-hook-registration.ts` | 3      | the description and the asserted substring `releaser lint-commit -c atomi_release.yaml` → `gitlint --staged --msg-filename`                                                                                                                            | node-owned consequence of **G21-1**: validator and validated file changed together                                                              |
| `scripts/ci/release.sh`                | 1      | `releaser release -c atomi_release.yaml` → `sg release -c atomi_release.yaml -i npm`                                                                                                                                                                   | parent-owned region replaced — upstream defect **G21-2**                                                                                        |
| `scripts/local/skills-sync.sh`         | 7      | the four-arm `rootUri` `case` → `resolve_pub_root`/`decode_uri_path`; `rm -rf "${vendor_dir}"` before `mv` → a move-aside backup with rollback                                                                                                         | parent-owned regions replaced — upstream defects **G21-3** and **G21-4**                                                                        |
| `scripts/release/bump.sh`              | 3      | `[ -z "${version}" ]` → `[[ -z ${version} ]]`; the bare `>VERSION` write → a `PACKAGE_ROOT`-anchored write plus the member `pubspec.yaml` stamp; the echo text                                                                                         | node-owned: release stamping is per-node. The `[ ]` → `[[ ]]` reshape is behaviour-preserving                                                   |

### G21.1d This artifact

| File                  | Classification                                                                                          |
| --------------------- | ------------------------------------------------------------------------------------------------------- |
| `UPSTREAM-CHANGES.md` | node-owned for this appended section; the inherited record above it is carried verbatim from the parent |

**Reconciliation.** 78 (G21.1a) + 12 (G21.1b) + 12 (G21.1c) + 1 (G21.1d) = **103**, equal to
`git diff --name-only 1ad2579703f20e419fa62c414cb6e4bf3eaac208 -- | wc -l` measured after this
edit. Against `--name-status` that is 78 A and 25 M, the 25 being G21.1b's 12 + G21.1c's 12 +
this artifact. No path appears in two rows and no changed path is absent from a row.

## G21.2 Documentation sweep — all 78 Markdown documents in the candidate

Population: `git ls-files -- '*.md'` returns **78** documents;
`git ls-files --others --exclude-standard -- '*.md'` returns none, so there is no untracked
document outside this population. **8** are changed against the accepted parent, **70** are inherited byte-identical
and unchanged. Every one is classified; no document is omitted and no group hides a member
with a different classification.

### G21.2a Changed documents — 8

| File                                                                 | Classification                  | Finding                                                                                                                            |
| -------------------------------------------------------------------- | ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `packages/diene_dart_lib/README.md`                                  | node-owned (new)                | package front page; ships in the publish archive                                                                                   |
| `packages/diene_dart_lib/CHANGELOG.md`                               | node-owned (new)                | release target; its opening block is gated against `atomi_release.yaml`'s `changelogTitle` by `scripts/validate/release-policy.sh` |
| `packages/diene_dart_lib/doc/diene_dart_lib.md`                      | node-owned (new)                | package documentation                                                                                                              |
| `packages/diene_dart_lib/skills/diene-dart-lib-usage/SKILL.md`       | node-owned (new)                | the shipped usage skill                                                                                                            |
| `packages/diene_dart_lib/skills/diene-dart-lib-usage/patterns.md`    | node-owned (new)                | shipped usage-skill asset                                                                                                          |
| `.claude/skills/vendor/diene_dart_lib/diene-dart-lib-usage/SKILL.md` | **vendored, machine-generated** | byte-identical to its generator; never hand-edited                                                                                 |
| `.claude/skills/vendor/diene_dart_lib/.../patterns.md`               | **vendored, machine-generated** | byte-identical to its generator; never hand-edited                                                                                 |
| `UPSTREAM-CHANGES.md`                                                | node-owned for this section     | this audit                                                                                                                         |

### G21.2b Inherited documents, unchanged against the accepted parent — 70

| #   | Group                          | Count | Members                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Classification and finding                                                                                                                                   |
| --- | ------------------------------ | ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | Root records                   | 3     | `CLAUDE.md`, `README.md`, `VALIDATOR-CHANGES.md`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | parent-owned, byte-identical, compliant — pointer indexes and the parent's own validator record                                                              |
| 2   | Root changelog                 | 1     | `Changelog.md`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | parent-owned, byte-identical, **claim now stale on this node — kept byte-identical by lead ruling; upstream debt, do not edit here.** See finding **N-1**    |
| 3   | Standards indexes and refs     | 41    | all of `docs/standards/**.md` except `docs/standards/nix/index.md`: `authorization/index.md`, `ci-cd/index.md`, `contracts/README.md`, the 21 `contributor-docs` documents (`audit/PHASE.md`, `audit/big-picture.md`, `audit/fact-check.md`, `audit/state-agent.md`, `checklist.md`, `classification.md`, `common/templates.md`, `common/writing-order.md`, `frontmatter.md`, `index.md`, `plan/PHASE.md`, `plan/classify.md`, `plan/diff-analysis.md`, `plan/review.md`, `plan/state-agent.md`, `structure.md`, `workflow.md`, `write/PHASE.md`, `write/scaffold.md`, `write/state-agent.md`, `write/write-file.md`), `conventional-commits/index.md`, `datetime/index.md`, `domain-driven-design/index.md`, `functional-practices/index.md`, `infisical/index.md`, `linting/index.md`, `semantic-release/index.md`, `service-tree/index.md`, `shell-scripts/index.md`, `software-design-philosophy/index.md`, `solid-principles/index.md`, `stateless-oop-di/index.md`, `taskfile/index.md`, `testing/index.md`, `three-layer-architecture/index.md`, `utilities/index.md`, `validation/index.md` | parent-owned, byte-identical, no new finding in this generation                                                                                              |
| 4   | Nix standard                   | 1     | `docs/standards/nix/index.md`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | parent-owned, byte-identical — **inherited Records 1–4 remain open**; see G21.5                                                                              |
| 5   | Skill triggers, non-nix        | 20    | `.claude/skills/<name>/SKILL.md` for `authorization`, `ci-cd-workflows`, `contributor-docs`, `conventional-commits`, `datetime`, `domain-driven-design`, `functional-practices`, `infisical`, `linting`, `semantic-release`, `service-tree`, `shell-conventions`, `software-design-philosophy`, `solid-principles`, `stateless-oop-di`, `taskfile-conventions`, `testing`, `three-layer-architecture`, `utilities`, `validation`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | parent-owned, byte-identical, each a single resolvable pointer to its standard                                                                               |
| 6   | Nix skill trigger              | 1     | `.claude/skills/nix/SKILL.md`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | parent-owned, byte-identical; split out because the inherited record classifies it separately as chain-root-born                                             |
| 7   | Developer and domain documents | 2     | `docs/developer/CommitConventions.md`, `docs/domain/README.md`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | parent-owned, byte-identical, compliant — `CommitConventions.md` still points at `atomi_release.yaml` as the machine-readable truth, which remains true here |
| 8   | Probe library README           | 1     | `probes/lib/README.md`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | parent-owned, byte-identical, compliant                                                                                                                      |

Group total: 3 + 1 + 41 + 1 + 20 + 1 + 2 + 1 = **70**. With the 8 changed documents that is
**78**, equal to the `git ls-files -- '*.md'` population.

`.claude/skills/vendor/**` is _not_ excluded from this sweep the way the inherited record
excluded it — the node now vendors two documents there, so they are classified explicitly in
G21.2a as vendored rather than silently dropped. They remain files this repository must
never hand-edit.

Non-Markdown documentation-adjacent files carried unchanged from the parent are outside the
Markdown population and unchanged in this generation:
`docs/standards/contributor-docs/scripts/` × `init-state.sh`, `mark-done.sh`, `next-file.sh`.
The one non-Markdown document the node adds, `packages/diene_dart_lib/LICENSE`, is the MIT
licence text required by the package-metadata gate and is node-owned.

## G21.3 Rule 1 — ownership-tag removal

**This document deliberately never reproduces the marker string verbatim.** Rule 1's search is
an unanchored substring match, so an audit that quoted the marker would match itself and turn
the mandated end-state check into a permanent false positive. Read the exact pattern from Rule 1
in `rules/IMPLEMENTATION-RULES.md`; below it is referred to as the _four-hash source marker_.

Measured with that mandated unanchored search, never `rg`:

- accepted parent `1ad2579`: **0** four-hash source markers. The parent already completed the
  removal recorded in the inherited "Ownership-tag removal" section.
- prior node head `09759ca`: **67** markers across **31** files.
- candidate working tree: **0** hits — `git grep` with Rule 1's pattern exits 1 with no output.

Adopting the accepted parent therefore removed all 67 markers from this node. No marker was
deleted by hand in this generation, no orphan marker was found, and no content under a marker
pair was removed. The three groups below account for all 31 files and all 67 markers.

**Standard note.** Rule 1 fixes the wording for a file whose only change in a parent/main-owned
region was marker removal:

> Only change in the main-owned region was required ownership-tag removal; no upstream content
> change.

This note applies verbatim to every file in groups A and B below, except the two group-A files
the inherited wave ruling deleted outright — a removed file has no surviving region for the
note to describe, and its removal is recorded in `VALIDATOR-CHANGES.md`, not here. Deleting a
marker is not an upstream content change, so no file earns a per-marker record — consistent
with the inherited ruling, which this section does not reopen.

**Group A — 14 files, 22 markers; now byte-identical to (or absent at) the accepted parent.**
`.coderabbit.yaml` (1), `.github/actionlint.yaml` (1), `.github/workflows/release.yaml` (1),
`.github/workflows/⚡reusable-precommit.yaml` (1), `.github/workflows/⚡reusable-release.yaml` (1),
`.github/workflows/🛡️merge-gatekeeper.yml` (1), `.prettierrc.yaml` (1), `CLAUDE.md` (3),
`README.md` (3), `nix/fmt.nix` (1), `nix/shells.nix` (4), `tasks/Taskfile.secret.yaml` (1),
plus the two files the wave ruling retired, `probes/many-owner-schema.ts` (1) and
`scripts/validate/many-owner.sh` (2), which are absent at both anchors. None of these appears
in the 103-path change list, because the node now carries the parent's stripped bytes exactly.
Standard note applies.

**Group B — 10 files, 38 markers; still differ from the parent for node reasons.**
`.github/dependabot.yml` (2), `.github/workflows/ci.yaml` (7), `.gitignore` (3),
`Taskfile.yaml` (3), `nix/env.nix` (8), `nix/packages.nix` (5), `nix/pre-commit.nix` (4),
`scripts/ci/setup.sh` (1), `scripts/local/skills-sync.sh` (4),
`scripts/validate/skills-freshness.sh` (1). Standard note applies to the parent-owned region of
each: the only change there was marker removal. Their remaining deltas are classified in
G21.1b and G21.1c and are separate from the tag removal.

**Group C — 7 files, 7 markers; node-born files that do not exist at the accepted parent.**
`.github/workflows/` × `cd.yaml` (1), `⚡reusable-analyze.yaml` (1), `⚡reusable-deadcode.yaml` (1),
`⚡reusable-nix-check.yaml` (1), `⚡reusable-package-validate.yaml` (1), `⚡reusable-publish.yaml` (1),
`⚡reusable-test.yaml` (1). These lost their markers too, but the standard note is **not** used
for them: they have no parent-owned region, so there is no main-owned region for the note to
describe. They are node-owned in full.

Reconciliation: 14 + 10 + 7 = **31** files; 22 + 38 + 7 = **67** markers; **0** remain.

## G21.4 Upstream-owned defects and upstream-owed content found in this generation

**Yes — upstream-owned defects were found.** The final tally, after the rulings below:

- **six defects** — **G21-1** … **G21-6**;
- **three upstream-owed but non-defect entries** — **G21-7** (withdrawn as a defect; see below),
  **G21-8**, **G21-9**;
- **one stale parent-owned document** — **N-1**, in G21.5.

All of them sit in accepted-parent bytes. The nine numbered records are carried as a **local
deviation on this node**, which Rule 5 permits only as a recorded state, not as a resolution,
while N-1 is carried as debt with **no** local edit at all. Lead `paloma` owns the call on
whether each is pushed upstream and the local fork reverted.

**One record changed classification after it was first written.** **G21-7** was reported twice as
a defect and is now **withdrawn**: a lifecycle trace showed the fixture commit it describes runs
before any hook is installed, so the parent has nothing to repair. Its bypass form was separately
settled by lead ruling — the blanket `--no-verify` replaced with a specifically named skip — and
that correction stands regardless of the withdrawal. The defect count above is 6, not 7, for this
reason; the full history of the claim is preserved in the record itself rather than deleted.

### G21-1. `a-releaser-commit` is wired to a binary the parent does not provide

- **File/region:** `nix/pre-commit.nix`, the `a-releaser-commit` hook (parent-owned).
- **What:** the parent sets `enable = true` with
  `entry = "releaser lint-commit -c atomi_release.yaml"`, but no accepted-parent surface
  provides a `releaser` binary. `nix/packages.nix` has no such attribute; `nix/env.nix` carries
  the comment `# C2: sg is retained only until tools/releaser is published at step 2p` and its
  `releaser` group contains `sg`; `scripts/validate/binary-smoke.sh` skips the check with
  `⏭️ releaser binary awaits the C2 step-2p tools/releaser publish`; and the parent's own
  `probes/features.json` row for `releaser-hook-registration` carries
  `"deferredUntil": "tools/releaser step 2p publish"`. Upstream should disable the hook until
  the binary lands, or point it at a tool that exists.
- **Why:** the hook-wiring clause in `rules/IMPLEMENTATION-RULES.md` is explicit — never wire a
  hook before the thing it invokes exists, because a missing-entry hook is a branch-wide commit
  block. An enabled `commit-msg` hook whose entry is not on `PATH` blocks every commit,
  including the commit that would fix it.
- **Local deviation carried:** the entry is
  `${packages.gitlint}/bin/gitlint --staged --msg-filename`, with `gitlint` added to
  `nix/packages.nix` (`dart-lib-tools`) and to the `lint` group, and a new node-owned
  `.gitlint`. The coupled surfaces were changed together:
  `probes/releaser-hook-registration.ts` now asserts the gitlint registration, and
  `scripts/validate/release-policy.sh` asserts that `.gitlint`'s `types` list is
  byte-identical to `atomi_release.yaml`'s type vocabulary — verified in this candidate, both
  read `amend,build,chore,ci,config,dep,docs,feat,fix,perf,refactor,style,test`.

### G21-2. `scripts/ci/release.sh` invokes the same unpublished binary

- **File/region:** `scripts/ci/release.sh:8` (parent-owned).
- **What:** the parent runs `releaser release -c atomi_release.yaml`. The reusable release
  workflow invokes this script inside `nix develop .#releaser`, a shell whose `releaser` group
  provides `sg`, not `releaser`, so the release job cannot succeed as shipped.
- **Why:** same basis as G21-1 — a wired entry point whose binary does not exist. This one
  fails at release time rather than commit time, which is later and more expensive.
- **Local deviation carried:** `sg release -c atomi_release.yaml -i npm`, which uses the
  stand-in the parent's own dev-shell group already provides.

### G21-3. Pub `rootUri` resolution mishandles URI authority and percent-encoding

- **File/region:** `scripts/local/skills-sync.sh`, the `.dart_tool/package_config.json` loop
  (parent-owned; the parent already ships Pub support in this universal synchronizer).
- **What:** the parent resolves a package root with
  `file://*) package_root="$(realpath -m "${root_uri#file://}")"`. A `file://localhost/…` URI
  therefore resolves to the relative path `localhost/…`, and a percent-encoded root — a package
  directory containing a space arrives as `%20` — is never decoded, so the directory test fails
  and the package's skills are silently skipped. `rootUri` is a URI, not a path.
- **Why:** silently skipping a skill-bearing package makes the synchronizer publish an
  incomplete vendor tree while exiting green. It is generic Pub handling, not Dart-template
  content, so it belongs upstream.
- **Local deviation carried:** `resolve_pub_root` (explicit `file://localhost/`, `file:///`,
  rejected-authority, absolute and relative arms) plus `decode_uri_path`.

### G21-4. The vendored-skills tree is destroyed before its replacement lands

- **File/region:** `scripts/local/skills-sync.sh`, the vendor replacement at the end of the
  script (parent-owned).
- **What:** the parent does `chmod -R u+w "${vendor_dir}"`, then `rm -rf "${vendor_dir}"`, then
  `mkdir -p`, then `mv "${staging}" "${vendor_dir}"`. Any failure or signal between the `rm` and
  the `mv` leaves the repository with no vendored skills and nothing to restore.
- **Why:** the destructive step precedes the committing step, and there is no rollback. The same
  atomic-replacement discipline `rules/AUTHORING-RULES.md` requires for shared executables
  applies here.
- **Local deviation carried:** the old tree is moved aside into a sibling swap directory, the
  new tree is moved into place, a `swap_committed` flag tells `cleanup` whether to roll back or
  discard, and `INT`/`TERM` traps plus exit-status propagation were added.

### G21-5. A root-relative script never establishes the repository root

- **File/region:** `scripts/ci/setup.sh` (parent-owned).
- **What:** the parent script uses `compgen -G '*.slnx'` and `./scripts/local/skills-sync.sh`,
  both of which assume the current directory is the repository root, but it never sets it. Run
  from any subdirectory it silently skips the restore and then fails on the relative path.
- **Why:** an implicit premise that the document — here, the script — never establishes. Generic
  to every node built from this parent.
- **Local deviation carried:** `root_dir="$(git rev-parse --show-toplevel)"; cd "${root_dir}"`.

### G21-6. Mutation probes leave their sabotage unrestored on an early failure

- **File/region:** `probes/hook-shellcheck.ts` and `probes/release-type-vocabulary.ts`, the
  `run` bodies (parent-owned).
- **What:** both write a sabotage into a tracked file and then assert red, with no `finally`. If
  the assertion throws, the mutated bytes stay in the sandbox and the evidence of what was
  mutated is lost.
- **Why:** a probe that can leave the tree dirty makes every later row in the same sandbox
  suspect, and losing the mutated bytes removes the only evidence that the sabotage was the one
  intended.
- **Local deviation carried:** both bodies wrapped in `try`/`finally` calling
  `preserveMutationBeforeRestore`, which writes the mutated file under `.probe-evidence/<id>/`
  and restores the original in its own `finally`. The `expectedImpact` change in the same hunks
  is _not_ part of this record: it is node-caused, because the node added the
  `release-policy-values` row that those files now feed.

### G21-7. A probe's fixture-seeding commit carries a redundant hook skip

**CLOSED — not an upstream defect.** This record was twice reported as a defect and is now
withdrawn on evidence. The correction is stated before the detail because a reader scanning the
defect list must not action a defect that no longer exists.

- **File/region:** `probes/hook-infisical-full.ts`, the mutation's fixture commit (parent-owned).
- **What the record claimed, retired verbatim:** "the probe seeds history with
  `git … commit -qm probe-secret` before running the mechanism under test. That commit runs the
  repository's `commit-msg` hook, so the hook aborts the probe's setup rather than the probe
  exercising the full-history scan it exists to test." A second pass narrowed the blame from the
  `commit-msg` hook to the infisical scan but kept the defect classification. **Both readings are
  withdrawn: no hook runs at that commit at all.**
- **Why it is withdrawn — lifecycle trace by `luan`, relayed by lead `paloma` (2026-08-03).** The
  fixture commit is not policed, because no hooks are installed when it runs:
  1. `probes/hook-infisical-full.ts` declares **no `setup` block** — verified here, the module
     has `contractVersion`, `sandbox` and `probes` only, while 17 sibling probes do declare one.
     So nothing enters a dev shell before the probe body.
  2. Within the mutation body the fixture commit is the **first** shell invocation; the only
     `nix develop` call sits on the line after it. Verified by reading the body in order.
  3. CyanPrint re-initialises a **hook-free** `.git` for the sandbox and never installs hooks.
     This step is owned by the CyanPrint harness and is **not verifiable from this repository** —
     no `git init`, `pre-commit install`, `hooksPath` or `.git/hooks` reference exists anywhere
     under `probes/`. It is recorded on `luan`'s trace, attributed rather than re-derived.
- **Consequence for the classification.** The parent's probe was never being aborted, so the
  parent has nothing to fix and **nothing is owed upstream for this record**. It moves out of the
  defect set and joins G21-8 and G21-9 as an upstream-owed but non-defect entry: what is offered
  upstream is a defensive skip, not a repair.
- **Local deviation carried:** `SKIP=a-infisical,a-infisical-staged` on that one commit —
  **harmless and redundant**, retained by lead ruling. Both IDs resolve to real enabled hooks in
  `nix/pre-commit.nix` (`a-infisical` at line 103, `a-infisical-staged` at line 111), so the skip
  names existing mechanisms rather than suppressing an empty set, and it costs nothing if the
  sandbox lifecycle ever changes to install hooks.
- **Ruling applied (lead `paloma`, 2026-08-03), two parts.** First: the bypass-discipline clause
  in `rules/IMPLEMENTATION-RULES.md` **does** reach a synthetic fixture commit inside a probe
  sandbox, so the earlier blanket `--no-verify` was replaced with the named skip above. That
  correction stands on its own merits and is not undone by the withdrawal — a blanket bypass was
  the wrong form whether or not any hook was listening. Second, on the residual risk this audit
  raised: `a-releaser-commit` is **not active** at the fixture commit, so the narrow skip is to
  be kept as-is and **`a-releaser-commit` must not be added to it**.
- **Residual risk — CLOSED.** This audit had measured that gitlint with the repository's
  `.gitlint` rejects the literal message `probe-secret`
  (`CT1 Title does not follow ConventionalCommits.org format`) and warned that the `commit-msg`
  hook was outside the skip. That measurement is still correct and is left recorded, but it is
  **moot**: the hook it describes is never installed at that point in the sandbox lifecycle, so
  it cannot fire. The audit did not touch the probe at any stage.

### G21-8. A generic probe-harness helper lives in the parent's shared library

- **File/region:** `probes/lib/helpers.ts` (parent-owned; addition only, 0 parent lines removed).
- **What:** `preserveMutationBeforeRestore` is generic — it validates the evidence id and source
  path, writes the mutated bytes under `.probe-evidence/`, verifies the copy, and restores the
  original in a `finally`. It is consumed by two parent-owned probes and eight node-owned ones.
- **Why:** this is **not a defect**. It is generic content that landed in an upstream-owned file,
  which Rule 5 requires to be recorded rather than quietly forked. It should be adopted upstream
  together with G21-6, since the two parent probes depend on it.

### G21-9. An offline variant of the pre-commit check

- **File/region:** `flake.nix` (2 parent lines re-pointed) and the `offline ? false` parameter in
  `nix/pre-commit.nix` (additive).
- **What:** the node instantiates `pre-commit.nix` twice — once normally for the dev-shell hook,
  once with `offline = true` for `checks.pre-commit-check` — so `nix flake check` stays hermetic
  while the interactive hooks keep their full behaviour. The three network-dependent hooks
  disabled by the flag (`a-dart-analyze`, `a-dart-test`, `a-dart-package`) are node-owned.
- **Why:** **not a defect** in the parent, whose hooks are all hermetic. The knob itself is
  generic and the two re-pointed `flake.nix` lines are parent-owned, so it is recorded rather
  than forked in silence.

## G21.5 Relationship to the inherited parent record

The inherited record above is a **parent-line** record and stays exactly as written. Nothing in
it is erased, reworded, or reinterpreted here.

- Inherited **Records 1–4** are historical _parent_ findings against
  `docs/standards/nix/index.md`. That file is byte-identical to the accepted parent in this
  candidate, and re-checking Record 2 at its stated location confirms it is still live:
  `docs/standards/nix/index.md:342` still names `.claude/skills/nix/reference.md`, and
  `.claude/skills/nix/` still contains only `SKILL.md`. All four therefore remain **open and
  inherited**. They are not restated as dart-lib findings and this node did not attempt to fix
  them, because the file is parent-owned and unchanged here.
- The inherited **Ownership-tag removal**, **Enforcement removal and hook trim**, **shared
  payload**, **bundle check**, and **open items** sections describe the parent line. G21.3 above
  records only what this node's adoption of that parent did, and reaches the same ruling by
  applying it, not by amending it.
- Records **G21-1** … **G21-9** and finding **N-1** are **current dart-lib findings**, all first
  raised here. None of them overlaps an inherited record.

### N-1 — the root `Changelog.md` claim is stale: upstream debt, no local fix

**Read this before acting on the root changelog: do not edit, rewrite, or delete
`Changelog.md` from this node.** It is parent-owned, it is byte-identical to the accepted
parent in this candidate, and it must stay that way.

`Changelog.md` states: "All notable changes are generated by the release pipeline." On this node
that is no longer true. `atomi_release.yaml` points the changelog plugin at
`packages/diene_dart_lib/CHANGELOG.md`, and the git plugin's asset list no longer contains
`Changelog.md`, so nothing regenerates the root file. Its only remaining reference anywhere in
the candidate is the prettier exclude entry in `nix/fmt.nix`.

**Ruling applied (lead `paloma`, 2026-08-03).** The root file stays byte-identical to the
accepted parent and this is recorded as **upstream debt only**. Deleting or rewriting a
parent-owned document from a child violates standing ruling 4, so no node-local edit is
authorised — not even a corrective sentence. The stale claim is **non-blocking**: the Dart
member changelog, `packages/diene_dart_lib/CHANGELOG.md`, is the actual package and release
truth on this node, and it is gated — `scripts/validate/release-policy.sh` asserts that its
opening block is byte-identical to `atomi_release.yaml`'s `changelogTitle`, and the
`release-policy-values` row covers that gate. A reader who follows the release configuration
reaches the correct file; only the root document's own sentence is stale.

**What is owed upstream:** the accepted parent should either make the changelog target's
description follow the configured `changelogFile`, or say plainly that the root `Changelog.md`
describes the repository-root release flow and that a workspace child may retarget it. This
record is the debt; the child does not discharge it.

Owning the cause honestly: the falsification is **node-caused** — a node-owned configuration
change made a parent-owned document stale — but the correction is parent-owned, which is why it
lands here as debt rather than as a local edit. This is the one finding where the node created
the problem and is nonetheless barred from fixing it in place.

No other current finding is owed. In particular, the node's coupled surfaces agree where a gate
asserts they must: `.gitlint` matches `atomi_release.yaml`'s type vocabulary, and
`atomi_release.yaml`'s `changelogTitle` is asserted byte-identical to the opening block of
`packages/diene_dart_lib/CHANGELOG.md` by `scripts/validate/release-policy.sh`.

## G21.6 Verification — commands run and results

All commands were run from the candidate working tree through `direnv exec`.

| Check                        | Command                                                                                                                        | Result                                                                                                                     |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| Rule 1 end state (mandated)  | `git grep` with Rule 1's four-hash source-marker pattern, unanchored, no revision argument                                     | exit 1, no output — **0 hits**                                                                                             |
| Marker basis, prior head     | the same pattern with `-c` against `09759ca…`                                                                                  | 67 markers across 31 files                                                                                                 |
| Marker basis, parent         | the same pattern against `1ad2579…`                                                                                            | 0 hits                                                                                                                     |
| Changed-path population      | `git diff --name-only 1ad2579… --`                                                                                             | 103 paths after this edit (78 A, 25 M, 0 D; this artifact is one of the 25)                                                |
| Per-file byte accounting     | `git diff --numstat 1ad2579… --diff-filter=M --`                                                                               | 13 files with 0 deletions (G21.1b's 12 plus this append-only artifact); 12 files with deletions, each reconciled in G21.1c |
| `features.json` row set      | `jq` comparison of the parent file against the candidate's non-`diene/dart-lib` rows                                           | identical; also identical as an ordered prefix                                                                             |
| Vendored tree integrity      | `diff -r packages/diene_dart_lib/skills/diene-dart-lib-usage .claude/skills/vendor/diene_dart_lib/diene-dart-lib-usage`        | no differences                                                                                                             |
| Documentation population     | `git ls-files -- '*.md'` and `git ls-files --others --exclude-standard -- '*.md'`                                              | 78 tracked, 0 untracked                                                                                                    |
| Coupled release vocabularies | `yq -r '.types[].type' atomi_release.yaml` against `.gitlint`'s `types`                                                        | byte-identical lists                                                                                                       |
| N-1 root file preserved      | `git diff --stat 1ad2579… -- Changelog.md`                                                                                     | empty — byte-identical to the accepted parent, as the ruling requires                                                      |
| G21-7 named skip resolves    | `grep -n 'a-infisical' nix/pre-commit.nix`                                                                                     | both skipped IDs exist and are enabled (`a-infisical` line 103, `a-infisical-staged` line 111)                             |
| G21-7 residual risk (closed) | `gitlint --config .gitlint --msg-filename` on the literal fixture message `probe-secret`, run on a copy outside the repository | rejected: `CT1 …` — correct but **moot**; the `commit-msg` hook is never installed at that point in the sandbox lifecycle  |
| G21-7 withdrawal, part 1     | `grep -c 'setup:' probes/hook-infisical-full.ts` against `git grep -l 'setup:' -- 'probes/*.ts'`                               | 0 in this probe; 17 sibling probes do declare one — nothing enters a dev shell before the body                             |
| G21-7 withdrawal, part 2     | reading the mutation body in order                                                                                             | the fixture commit is the first shell invocation; the only `nix develop` call is on the following line                     |
| G21-7 withdrawal, part 3     | `git grep -n 'git init\|hooksPath\|.git/hooks\|pre-commit install' -- probes`                                                  | no hits — sandbox `.git` re-init is CyanPrint-owned and **not verifiable from this repository**; taken on `luan`'s trace   |
| Markdown formatting          | the flake's treefmt/prettier wrapper run on a copy of this file in an isolated directory                                       | clean, no reformatting                                                                                                     |

The formatting and gitlint checks were deliberately run against **copies** outside the
repository: a repository-wide `nix fmt` would touch files this audit does not own, and the merge
is shared and unresolved. No file other than `UPSTREAM-CHANGES.md` was edited, staged, formatted,
or restored by this audit. `probes/hook-infisical-full.ts` changed between the first and second
passes of this audit, but not by this audit — the lead made that edit when applying the G21-7
ruling, and the audit only re-measured it. Every count in G21.1, G21.2 and G21.3 was re-derived
after that edit and is unchanged: still 103 paths (78 A / 25 M / 0 D), still 13/12 on the numstat
split, still 78 documents, still zero marker hits.
