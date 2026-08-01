# Contributor Documentation Workflow

Systematically generate contributor documentation for a repository by analyzing git diffs, planning the doc structure, writing files with parallel agents, and auditing the result.

## When to Use

- Running `/contributor-docs`
- Documenting a new repo or feature branch
- Generating technical docs from code changes

## User Entry Points

```
/contributor-docs                    → Analyze current branch vs main, generate docs
/contributor-docs <base-branch>      → Analyze current branch vs specified base
```

There is deliberately **no phase-skip argument**. Resuming is driven by state, not by
a flag: a run always re-enters at `task-state.json`'s `currentPhase`, and every phase
depends on artifacts the previous one produced (write needs `doc-plan.yaml`; audit
needs written files). A flag that jumped straight to `write` or `audit` would have to
either fabricate those artifacts or fail, so it is not offered. To redo a phase,
transition state through its state-agent — that path is defined and validated.

## Reference Documentation

Knowledge about what contributor docs are, their structure, and formatting rules:

- [What are contributor docs](./index.md)
- [Folder structure](./structure.md)
- [Frontmatter schemas](./frontmatter.md)
- [Formatting checklist](./checklist.md)
- [Classification heuristics](./classification.md)

Skill-internal references (LLM operational instructions):

- [Body templates](./common/templates.md)
- [Writing order](./common/writing-order.md)

## Agent Taxonomy

| Type           | Spawning                        | State transition            | Purpose                               |
| -------------- | ------------------------------- | --------------------------- | ------------------------------------- |
| **Sub-agent**  | `Task` (no team), direct result | No                          | State reads/writes (haiku)            |
| **Team agent** | `Task` (with team), messaging   | Yes — corresponds to a step | Analysis, planning, writing, auditing |

## Orchestrator Model

```
ORCHESTRATOR (you = team lead)
├── SUB-AGENTS (stateless, direct result):
│   ├── plan-state-agent (haiku) — plan phase state reads/writes
│   ├── write-state-agent (haiku) — write phase state reads/writes
│   └── audit-state-agent (haiku) — audit phase state reads/writes
│
├── TEAM AGENTS (spawned via Task tool):
│   ├── diff-analyzer (sonnet) — reads git diff, catalogs all changes
│   ├── doc-planner (opus) — classifies changes, plans doc structure
│   ├── scaffolder (sonnet) — creates all files with frontmatter + TODOs
│   ├── doc-writer (sonnet) ×N — writes one doc file (file-processor loop)
│   ├── big-picture-auditor (opus) — holistic structure and coherence audit
│   └── fact-checker (sonnet) ×N — per-file accuracy audit (file-processor loop)
│
└── State: Per-phase state-agents handle all state writes. Orchestrator NEVER reads/writes JSON directly.
```

**Key principle:** The orchestrator NEVER reads step files directly. Always spawn a team agent and tell it which step file to read and execute.

**Every dispatched path is written from the repository root.** Agents are spawned with
the repo root as their working directory, so a path written relative to this
standard's own directory — scaffold.md addressed as write/scaffold.md — does not
resolve for them. Operational references are always spelled in full, starting from
docs/standards/contributor-docs. Relative links such as `./checklist.md` are for
humans reading this document in place; they are never what an agent is told to open.

This is mechanically checkable. From the repository root:

```bash
# Every backticked operational path in the workflow family must exist on disk.
grep -rhoE '`docs/standards/contributor-docs/[A-Za-z0-9/_.-]+`' docs/standards/contributor-docs/ \
  | tr -d '`' | sort -u \
  | while read -r p; do [ -e "$p" ] || echo "UNRESOLVED: $p"; done

# And no operational reference may be written relative to the standard's own directory.
grep -rnE '`(plan|write|audit|common)/[A-Za-z.-]+\.md`' docs/standards/contributor-docs/
```

Both must produce no output.

## Glossary

| Term             | Scope         | Description                                                 |
| ---------------- | ------------- | ----------------------------------------------------------- |
| **Module**       | Doc structure | Bounded context grouping (e.g., `user-management/`)         |
| **Section type** | Doc structure | Content category: feature, concept, algorithm, surface, ADR |
| **Tier**         | Write phase   | Dependency level for writing order (1-6)                    |
| **Doc plan**     | Plan phase    | YAML manifest listing all files to create with metadata     |
| **Scaffold**     | Write phase   | File with frontmatter + TODO notes but no body content      |

## Two-Level State

```
.contributor-docs/
├── task-state.json          # Overall: which phase, base branch, docs root
├── plan-state.json          # Plan phase steps
├── diff-summary.md          # Source-snapshot-bound analysis used by planning
├── doc-plan.yaml            # Approved documentation plan
├── doc-plan.gap-candidate.yaml # Transient candidate for one discovered-gap successor
├── write-state.json         # Write phase steps + tier tracking
├── audit-state.json         # Audit phase steps
├── big-picture-report.md    # Epoch/digest-stamped holistic audit artifact
├── write-tier-N/            # File-processor state per tier (created during write)
│   ├── state.json
│   └── findings/
├── fact-check/              # File-processor state for audit (created during audit)
│   ├── state.json
│   ├── epoch.json           # Required audit epoch + docs digest sidecar
│   └── findings/
└── transitions.log          # Append-only step transition log
```

## Task-Level State (`task-state.json`)

| Field          | Type   | Description                                                   |
| -------------- | ------ | ------------------------------------------------------------- |
| `currentPhase` | string | Active phase: `plan`, `write`, `audit`, `completed`, `failed` |
| `baseBranch`   | string | Base branch to diff against (default: `main`)                 |
| `docsRoot`     | string | Authoritative output directory (default: `docs/contributor`)  |
| `planFile`     | string | Path to doc plan YAML (`.contributor-docs/doc-plan.yaml`)     |

`docsRoot` is a normalized repository-root-relative directory other than `.`. It
must neither equal nor contain `.contributor-docs`, and `.contributor-docs` must not
contain it. These disjoint roots are the only dirty-worktree exceptions in the source
snapshot check below.

## Source Snapshot Invariant

`.contributor-docs/diff-summary.md` starts with the exact marked five-field record in
`docs/standards/contributor-docs/plan/diff-analysis.md#4-write-summary`. That artifact
binds planning to source, not merely to a prose summary of source.

The canonical capture and validation procedure is:

1. Read `baseBranch` and `docsRoot` from `task-state.json`; completely validate both.
2. Resolve `baseBranch^{commit}` and `HEAD^{commit}` once. Record them as `baseCommit`
   and `headCommit`. Run `git merge-base --all` on those two object IDs and require
   exactly one result, recorded as `mergeBaseCommit`.
3. Compute `diffDigest` as SHA-256 of the exact NUL-framed raw tree delta emitted by:

   ```bash
   LC_ALL=C git diff-tree --no-commit-id -r --raw -z --no-renames \
     --abbrev=64 "$merge_base_commit" "$head_commit" | sha256sum | cut -d ' ' -f1
   ```

   The raw record binds modes, complete blob object IDs, and paths without invoking a
   user-configured text diff driver.

4. Read `git status --porcelain=v1 -z --untracked-files=all`. Parse NUL records,
   including both paths of every rename or copy. Every reported path must equal or be
   below `.contributor-docs/` or the normalized `docsRoot`; otherwise the source is
   dirty and the check fails with the complete sorted outside-path set. A line-based
   parser or a parser that checks only one side of a rename is invalid.
5. `record-diff-analysis` validates that unbound candidate record, freshly hashes the
   complete diff-summary bytes, and records that hash in `plan-state.json`. Every later
   validation first requires a completely valid plan state with
   `diffSummaryReady: true`, a non-null `diffSummaryHash`, and a fresh SHA-256 of the
   complete diff summary equal to that recorded hash. Only then parse the marked record
   and require exactly its five fields; require `baseRef == task-state.baseBranch`,
   freshly resolve the base and HEAD to the recorded commits, recompute the unique merge
   base and raw-tree digest, and repeat the dirty-path check. Missing input is
   CANNOT-LOOK, never a match. `invalidate-diff-summary` is the sole operation allowed
   to consume a proven missing or mismatched binding.

Every plan, write, and audit state-agent runs the bound check before it reports a later
dispatch or mutates post-analysis state. The plan agent's `record-diff-analysis`
operation is the one unbound capture-to-binding edge. During later plan steps, any
mismatch selects only
`invalidate-diff-summary`, which returns to `diff_analysis` and clears downstream
identity and approval. Once task phase has reached `write`, `audit`, `failed`, or
`completed`, no safe rollback is defined: the state-agent reports
`SOURCE_DRIFT_BLOCKED` with the mismatched identities or outside dirty paths and leaves
all state and artifacts byte-identical. Cleaning a transient outside path permits a
retry only when every recorded source identity still matches; a committed source
change requires an explicit whole-run restart rather than an invented replan edge.

## Approved Plan Identity Invariant

`plan-state.json.planHash` is the immutable SHA-256 of the exact plan bytes the user
approved. The plan state-agent never rewrites that baseline after the handoff to
write. On first write-state creation, the write state-agent requires the completed,
approved seven-field plan state; matching task/plan paths equal to
`.contributor-docs/doc-plan.yaml`; the current source and diff-summary binding; and a
fresh hash of the live plan equal to `planHash`. It initializes
`write-state.json.authorizedPlanHash` to that approved hash.

Only a discovered-gap transition may authorize a successor. The orchestrator may
prepare `.contributor-docs/doc-plan.gap-candidate.yaml`, but it never edits the live
plan. `authorize-gap-plan` proves that the candidate adds exactly the reported gap
entries and reporter links and records its hash successor without changing the live
plan. `apply-gap-plan` installs those exact candidate bytes and advances
`authorizedPlanHash`; no other operation may change that field.

Every write and audit assessment validates the complete authority chain. Starting at
the immutable `plan-state.planHash`, it walks `gapsResolved` in append order, requiring
each cleared record's `planMutation.fromPlanHash` to equal the cursor before advancing
to `toPlanHash`. A live transition must extend that same cursor. With no live gap, the
derived cursor, `authorizedPlanHash`, and a fresh hash of the live plan must be equal,
and the candidate sidecar must be absent. From `planned` onward the live transition's
`toPlanHash` is the current authorized/live hash and the sidecar is absent.

The only live-plan mismatch that may mutate anything is the fenced `enqueued` crash
recovery: stored authority is fully valid, `authorizedPlanHash == fromPlanHash` equals
the derived cursor, the live plan already hashes to `toPlanHash`, and the candidate is
absent because its rename committed before the write-state rename. `apply-gap-plan`
may finish that pending state update. Any other missing plan, broken lineage, or live
hash mismatch is
`PLAN_DRIFT_BLOCKED: expected=<hash> actual=<hash-or-absent>` and leaves state,
processor files, task phase, and audit artifacts byte-identical.

The source-snapshot dirty-path exception deliberately permits `.contributor-docs/`, so
`sourceSnapshotCurrent: true` does not imply that either plan is authorized. Source
and plan identity remain separate ordered guards on every later dispatch and update.

### Clean Start (the first transition)

A clean invocation has no `.contributor-docs/` directory at all. Exactly one
component may create it: the **plan state-agent in `create` mode**. The write and
audit state-agents never create `task-state.json`; they only create their own
phase-state file when their phase is first entered, and they refuse to run if
`task-state.json` is absent.

`create` mode, run by the plan state-agent, is the only bootstrap path:

1. `mkdir -p .contributor-docs` — the directory is created, not assumed.
2. Write `plan-state.json` **first**, with the initial phase schema:

   ```json
   {
     "step": "diff_analysis",
     "diffSummaryReady": false,
     "diffSummaryHash": null,
     "planFile": null,
     "planHash": null,
     "reviewFeedback": null,
     "approved": false
   }
   ```

3. Write `task-state.json` **last**, with the initial schema:

   ```json
   {
     "currentPhase": "plan",
     "baseBranch": "<from arguments, default main>",
     "docsRoot": "<from arguments, default docs/contributor>",
     "planFile": null
   }
   ```

4. Validate every field before reporting success, then log the transition.

**`task-state.json` is the commit marker.** Creation spans two atomic renames, so
there is a window between them. Writing the phase file first means a crash in that
window leaves a phase file with no task file — visibly incomplete, and the next
`create` finishes it. The opposite order would leave a complete-looking task file
with no phase state, which every retry reads as "already initialized" and hands to
`assess`, stranding the workflow with nothing to assess.

Each write is atomic — temp file in `.contributor-docs/` then `mv` — so no individual
file is ever half-written. Atomicity plus commit-marker ordering is what makes the
two-file bootstrap crash safe and the retry path deterministic. The full branch table
for partial states lives in
`docs/standards/contributor-docs/plan/state-agent.md`.

Each phase state-agent applies rules 1, 2, 5 and 6 to its own phase-state file
(`write-state.json`, `audit-state.json`) with that phase's initial step.

## Top-Level State Machine

```
task-state.json.currentPhase:
  plan → write → audit → completed
          ↑        ↓
          └────── failed --(no-current-error reset)--> audit
            audit content repair
```

### Phase 1: Plan

```
[diff_analysis] → [classify] → [review] → completed
    team(S)         team(O)      inline
```

Dispatch: `docs/standards/contributor-docs/plan/PHASE.md`

### Phase 2: Write

```
[scaffold] → [scaffold_prepared] → [write_tier_1] → ... → [write_tier_6] → completed
     │                  ↑             file-processor          file-processor
     └→ [scaffold_blocked] ───────────┘ loop(S)×N               loop(S)×N
```

Dispatch: `docs/standards/contributor-docs/write/PHASE.md`

### Phase 3: Audit

```
[big_picture] → [fact_check] → completed
    team(O)      file-processor
                   loop(S)×N
```

Dispatch: `docs/standards/contributor-docs/audit/PHASE.md`

## Phase Dispatch

**On invocation, spawn a state-agent to assess `task-state.json`, then dispatch:**

| `currentPhase` | Action                                                                                                                                                      |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| No state file  | Parse arguments (base branch), spawn the **plan** state-agent in `create` mode (see [Clean Start](#clean-start-the-first-transition)), then start Plan      |
| `plan`         | Spawn plan state-agent to assess, dispatch per `docs/standards/contributor-docs/plan/PHASE.md`                                                              |
| `write`        | Spawn write state-agent to assess source and plan authority, then dispatch per `docs/standards/contributor-docs/write/PHASE.md`                             |
| `audit`        | Spawn audit state-agent to assess source and the complete plan-authority chain, then dispatch per `docs/standards/contributor-docs/audit/PHASE.md`          |
| `completed`    | Spawn the audit state-agent to reassess source, plan authority, and completed evidence; report completion and generated files only while all remain current |
| `failed`       | Spawn audit and write state-agents to reassess source, plan authority, and recovery evidence; those identity guards preempt every fenced recovery row below |

Every non-bootstrap row above begins with the named phase state-agent's `assess` mode.
Source drift is evaluated first. The one valid `enqueued` `apply-gap-plan` crash tuple
is evaluated next during write; ordinary plan drift is then evaluated before every
remaining write, audit, recovery, terminal, or completed-reporting row. For task phase
`completed`, `SOURCE_DRIFT_BLOCKED`, `PLAN_DRIFT_BLOCKED`, or invalidated
accepted-warning evidence suppresses the completion report. For task phase `failed`,
either named identity outcome suppresses every row in Failed-Phase Dispatch.

**Transition logging:** When advancing phases, the state-agent appends:

```bash
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) phase-transition from={old_phase} to={new_phase}" >> .contributor-docs/transitions.log
```

### Failed-Phase Dispatch

Audit is the only phase permitted to create task phase `failed`, but content repair
temporarily routes that fenced failure through the ordinary write machinery. Dispatch
uses the complete audit/write/task triple:

1. Spawn both audit and write state-agents in `assess` mode. Validate all state,
   current audit stamps, the complete error-to-path mapping, and `auditRepair` before
   selecting a row below. Source drift preempts plan drift; plan drift then preempts
   every repair, reset, resume, and terminal edge. Audit dispatch evaluates these same
   fenced rows when task phase is still `audit`.
2. With audit step `failed`, task phase `audit`, write step `completed`, and
   `auditRepair` null or bound to an older audit epoch, the audit-state failure rename
   committed before its paired task-phase rename. Invoke only
   `resume-failed-task-phase`, then reassess from task phase `failed`; never infer
   completed repair from this tuple. A current `replaying` marker here is inconsistent
   state and must not be normalized by this recovery.
3. With audit step `failed`, if `repairOutOfScope` is non-empty, report
   `REPAIR_OUT_OF_SCOPE` with the exact current errors and mutate nothing. This includes
   a skipped/non-queued reporting document or an unsupported topology change. The
   declared proposed-path addition for a stamped `missing-dependency` is not out of
   scope; it uses the normal discovered-gap transition after the reporting document is
   reopened. Assessment reports this outcome as `none` at every active audit step, so a
   partial big-picture result cannot short-circuit fact-check.
4. With audit step `failed`, task phase `failed`, write step `completed`, derived
   `currentContentErrors == 0`, and non-empty `writeDriftBlocked`, report
   `WRITE_DRIFT_BLOCKED: <complete sorted normalized paths>` and mutate nothing. This
   named authority outcome means external byte drift prevents evidence reset; it is not
   `INVALID_FAILED_STATE`.
5. With audit step `failed`, task phase `failed`, write step `completed`, and derived
   `currentContentErrors > 0`, present the current errors and select the exact queued
   `repairPaths` they name. Invoke write state-agent `reopen-audit-repair`; direct
   document edits are forbidden. It clears repair-tier processors, retains write
   hashes, installs the current epoch/digest/path-bound `auditRepair: replaying`
   marker, reopens only those paths, and then moves task phase to `write`.
6. With audit step `failed`, task phase still `failed`, write step `write_tier_N`, and
   a matching `auditRepair: replaying` marker, the write-state rename committed before
   its task-phase rename. Invoke only `resume-audit-repair-phase`, then enter ordinary
   `write` dispatch.
7. Task phase `write` always follows the ordinary write row. Repair writers receive
   their stamped errors plus the current complete normalized planned-path set. Only a
   `missing-dependency` whose proposed path is still absent becomes a structured `GAPS`
   report; one whose target joined the plan is downgraded to link-only repair. When all
   tiers complete, write state-agent freshly verifies the marked paths, atomically
   changes the marker to `completed`, then moves task phase to `audit`. A crash between
   those renames retries only the task-phase handoff.
8. With task phase `audit`, audit step `failed`, write step `completed`, and the exact
   current `auditRepair: completed` marker, invoke audit reset. It starts the next
   epoch and cleans every prior-epoch artifact before ordinary audit work resumes.
9. A failed audit with no **currently stamped** content errors represents a hard-agent
   or freshness retry rather than content repair. It may reset directly from task
   phase `failed` only while completed write provenance still freshly matches disk;
   stale counters alone never authorize either repair or reset. A mismatch is the
   `WRITE_DRIFT_BLOCKED` outcome in row 4.
10. If audit step is `big_picture`, `auditEpoch >= 2`, every reset field has its fresh
    value, and task phase is still `failed`, a direct-reset commit needs reconciliation.
    Resume cleanup without incrementing the epoch and finish task phase
    `failed → audit`. Post-repair stale-artifact cleanup is reached from ordinary audit
    dispatch through `resetResumeRequired`.
11. Any other combination is `INVALID_FAILED_STATE`; report the exact triple and
    mutate nothing.

These rows make both recovery cycles reachable after invocation boundaries while
keeping their authorities separate: write provenance authorizes document replacement,
and the audit epoch commit marker authorizes evidence invalidation.

## File-Processor Pattern

The write phase (per-tier) and audit fact-check use the file-processor loop. Scripts are in `scripts/`:

```bash
# 1. Initialize: pipe file list into init-state.sh.
# Use printf, not echo: Bash's echo emits the backslash-n literally, which
# records ONE pending file named "file1.mdx\nfile2.mdx" instead of two.
printf '%s\n' file1.mdx file2.mdx | bash docs/standards/contributor-docs/scripts/init-state.sh <state-file> '<source-paths>' <N> '<output-dir>'

# 2. Loop: get next batch and spawn agents
bash docs/standards/contributor-docs/scripts/next-file.sh <state-file> --batch <N>

# 3. Validate the phase-specific durable result first.
#    Write: state-agent record-write verifies returned/start/disk hashes.
#    Audit: verify epoch, digest, and fresh per-file hash.

# 4. Only after that validation succeeds:
bash docs/standards/contributor-docs/scripts/mark-done.sh <state-file> <filename>
```

Progress survives context loss. Re-running resumes from where it left off.

## Rules

### Autonomy

1. Proceed autonomously through diff analysis and classification. Stop at the review gate and wait for user approval.
2. If the plan is rejected, return to classify with user feedback.

### Safety

3. Never overwrite existing documentation files without user confirmation.
4. Never commit generated docs automatically.

### Conventions

5. All generated files must pass [checklist.md](./checklist.md).
6. Follow the tier-based writing order in [writing-order.md](./common/writing-order.md). Never skip tiers.
7. Reference body templates in [templates.md](./common/templates.md) for every file written.

### State

8. Orchestrator NEVER reads/writes state JSON directly — always use state-agents.
9. Team agents NEVER update state — they report back, orchestrator uses state-agents.

## Prerequisites

- Git (for diff analysis)
- `jq` (for file-processor scripts)
- Current branch must have commits ahead of the base branch

## Related Skills

None — this is a standalone documentation generation pipeline.
