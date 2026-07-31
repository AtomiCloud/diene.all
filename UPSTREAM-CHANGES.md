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

All twelve files involved appear in the classification table above, including the eight
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
all 19 hooks, so no failure output needed recording.

## Open items deliberately not recorded

- The point-at-truth rule's documentation home is **pending the user's ruling**. The rule
  was applied to this node's content; no home was invented for its text, here or
  anywhere else.
- The Shared deletions (contributor docs, lychee) are pending user confirmation and are
  out of scope for this node.
