# Plan State Agent — Sub-Agent (Haiku)

**Sub-agent. Stateless.** Returns result directly to orchestrator.

Manages state transitions for the Plan phase. The orchestrator NEVER reads/writes state JSON directly — this agent handles all state operations.

## Agent Context

- Working directory: repo root
- State files: `.contributor-docs/plan-state.json`, `.contributor-docs/task-state.json`
- Mode: {create|assess|update}

## Mode 0: Create (clean start — this agent owns it)

When prompted: "Create task state: baseBranch={branch} docsRoot={dir}"

This agent is the **only** owner of the first transition. The write and audit
state-agents never create `task-state.json`.

### `task-state.json` Is the Commit Marker

Creation writes **two** files, so it has two atomic renames and a window between
them. The order is chosen so that window is always recoverable:

> **`plan-state.json` is written first. `task-state.json` is written last, and its
> existence is what declares the bootstrap complete.**

A crash between the renames therefore leaves a phase file with no task file — an
obviously incomplete bootstrap that the next run can finish. The reverse order would
leave a complete-looking task file with no phase state, which every retry would read
as "already initialized" and hand to `assess`, stranding the workflow with nothing to
assess.

### Procedure

1. `mkdir -p .contributor-docs`
2. Inspect what already exists and branch:

   | On disk                | Meaning                          | Action                                                                                        |
   | ---------------------- | -------------------------------- | --------------------------------------------------------------------------------------------- |
   | Neither file           | Clean start                      | Continue at step 3                                                                            |
   | `plan-state.json` only | Crash after the first rename     | **Resume the bootstrap**: re-validate it, then continue at step 4                             |
   | Both files             | Already initialized              | Report `ALREADY_INITIALIZED`, switch to Mode 1                                                |
   | `task-state.json` only | Must not happen under this order | Report `CORRUPT_STATE: task state without plan state` and refuse — do not guess a phase state |

3. Write `.contributor-docs/plan-state.json` (the canonical plan schema, matching
   `docs/standards/contributor-docs/plan/PHASE.md`):

   <!-- canonical-block: plan-state-schema -->

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

4. Write `.contributor-docs/task-state.json` — **last**, as the commit marker:
   ```json
   {
     "currentPhase": "plan",
     "baseBranch": "{branch, default main}",
     "docsRoot": "{dir, default docs/contributor}",
     "planFile": null
   }
   ```
5. Validate before reporting success. Every field is checked, not just parseability:
   - both files parse as JSON;
   - `currentPhase` ∈ `plan|write|audit|completed|failed`;
   - `step` ∈ `diff_analysis|classify|review|completed`;
   - `diffSummaryReady` and `approved` are booleans;
   - `diffSummaryHash` and `planHash` are a lowercase SHA-256 or `null`;
   - `planFile` and `reviewFeedback` are a string or `null`;
   - `baseBranch` resolves to an existing ref.
   - `docsRoot` is a normalized, non-root repository-relative directory disjoint from
     `.contributor-docs` as required by the workflow source-snapshot invariant.

   On any failure, remove both files so the next run sees a clean start rather than a
   half-built pair, and report `CREATE_FAILED: <reason>`.

6. Append `$(date -u +%Y-%m-%dT%H:%M:%SZ) phase=plan from=none to=diff_analysis`
   to `.contributor-docs/transitions.log`.

**Atomic writes.** Every write in this file — Mode 0 and Mode 2 alike — goes
through a temp file in `.contributor-docs/` followed by `mv`, so an interrupted
run never leaves a partially written state file. Atomicity per file plus the
commit-marker ordering is what makes the two-file creation crash safe.

### Recovery Is Retryable

Re-running `create` after a crash is always legal and always converges: the branch
table sends a `plan-state.json`-only tree back into step 4, and a complete pair to
`assess`. The retry path is the normal path, not a special repair mode.

### Report Format

```
CREATED: plan-state.json, task-state.json
CURRENT_STEP: diff_analysis
```

or, when finishing an interrupted bootstrap:

```
RESUMED_BOOTSTRAP: task-state.json
CURRENT_STEP: diff_analysis
```

## Mode 1: Assess (determine current state)

When prompted: "Assess plan phase state"

### Procedure

1. Read and completely validate `.contributor-docs/plan-state.json`.
2. Read and validate `.contributor-docs/task-state.json` for shared context.
3. Check whether `.contributor-docs/diff-summary.md` and
   `.contributor-docs/doc-plan.yaml` exist, and freshly hash each existing artifact.
4. Parse the diff summary's marked source-snapshot record and run the canonical bound
   validation from `docs/standards/contributor-docs/workflow.md`, including the live
   summary hash after `record-diff-analysis`. Derive `sourceSnapshotCurrent` and the
   complete binding/identity/outside-dirty reason.
5. Derive whether the live hashes equal their recorded values. After `diff_analysis`, a
   diff-summary mismatch preempts every later dispatch and selects only
   `invalidate-diff-summary`; a source-snapshot mismatch has the same precedence. A
   plan mismatch preempts `review` and `completed` dispatch
   and selects `invalidate-plan`, but it does not block `classify`: on first entry the
   candidate may be absent, and after rejection the classifier is expected to replace
   the retained rejected-plan bytes. Report every mismatch without mutation; the named
   invalidation operation or `record-classification` validates and binds the complete
   next state.
6. Report current state without mutation.

### Report Format

```
CURRENT_STEP: <step from plan-state.json>
CONTEXT:
- diffSummaryReady: <true|false>
- diffSummaryHash: <64 lowercase hex | absent>
- diffSummaryHashCurrent: <true|false>
- sourceSnapshotCurrent: <true|false>
- sourceSnapshotMismatch: <none | summary binding, identity/digest mismatch, or sorted outside dirty paths>
- planFile: <exists|absent>
- planHash: <64 lowercase hex | absent>
- planHashCurrent: <true|false>
- approved: <true|false>
- reviewFeedback: <present|absent>
```

## Mode 2: Commanded Plan-State Operations

When prompted: `Update plan state: {OPERATION_JSON}`

The object must name exactly one legal operation below. A generic field patch is
`UPDATE_REFUSED: operation required`; callers never provide a desired `step`,
`approved` flag, artifact hash, or task phase.

### Universal Procedure

1. Read and completely validate both state files and the source step's stored
   structural invariants. Live artifact freshness is operation-specific:
   `invalidate-diff-summary` is allowed to prove the summary or source-snapshot mismatch that every later
   operation must refuse, and `invalidate-plan` is allowed to prove the plan mismatch
   that every other review or completion operation must refuse.
2. Run the canonical source-snapshot validation. `record-diff-analysis` validates the
   unbound candidate record and binds its fresh complete-artifact hash.
   `invalidate-diff-summary` instead requires the summary binding or live identities to
   be non-current. Every other operation requires the fully bound validation current.
3. Resolve every artifact path from the repository root, refuse path escape, and
   freshly hash the exact bytes.
4. Build the operation's complete candidate object; never merge caller fields into
   state.
5. Validate the candidate and target-step invariants before writing.
6. Write through a temp file in `.contributor-docs/` plus atomic rename.
7. Append the transition log only after the rename.

### Legal Operations

| Operation                     | Legal source                         | Required validation and atomic effect                                                                                                                                                                                                                                                                                                         |
| ----------------------------- | ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `record-diff-analysis`        | `diff_analysis`                      | Require `.contributor-docs/diff-summary.md` to exist, cover the complete captured diff, and carry a current exact five-field source snapshot. Freshly hash it; set readiness/hash, clear downstream identity/approval, and move to `classify`.                                                                                                |
| `invalidate-diff-summary`     | `classify`, `review`, or `completed` | Prove the live summary is absent/hash-mismatched or its source snapshot is non-current. Restore the untouched `diff_analysis` object and clear all downstream identity, feedback, and approval.                                                                                                                                               |
| `record-classification`       | `classify`                           | Require current source and matching summary hash. Parse and completely validate `.contributor-docs/doc-plan.yaml`, including exact equality with task-state `docsRoot`, diff coverage, unique normalized relative output paths, exhaustive type/tier rules, sources, and cross-links. Record path/hash, clear feedback, and move to `review`. |
| `reject-plan`                 | `review`                             | Require explicit non-empty user feedback and a fresh plan hash equal to `planHash`. Preserve the reviewed plan identity and feedback, keep `approved: false`, and move to `classify` for a new classification.                                                                                                                                |
| `invalidate-plan`             | `review` or `completed`              | Require the diff-summary hash still matches and prove the live plan is absent or its fresh hash differs from `planHash`. Clear `planFile`, `planHash`, and any approval; set fixed feedback `Plan changed after classification; rebuild from current bytes.`, and move to `classify`.                                                         |
| `approve-plan`                | `review`                             | Require an explicit user approval, current source, current summary/plan hashes, and a still-valid complete plan. In one write set `approved: true`, clear feedback, and move to `completed`.                                                                                                                                                  |
| `advance-task-phase-to-write` | `completed`                          | Require completed invariants, task phase `plan`, current source, and current artifact hashes. Atomically update only task phase and plan path. A retry observing those same task values is an idempotent success.                                                                                                                             |

An explicit user decision is input evidence, not a caller-selected state value. The
state-agent accepts it only in `reject-plan` or `approve-plan` at `review`, and binds
it to the fresh `planHash` before installing the corresponding fixed candidate.
Neither invalidation accepts caller feedback or a desired hash.
`invalidate-diff-summary` derives the summary or source mismatch and restores the exact initial object;
`invalidate-plan` derives its mismatch and fixed classifier feedback.

### Complete-Object Validation

- The object has exactly the seven canonical fields shown in Mode 0; unknown or
  missing fields are refused.
- `step` is one of `diff_analysis`, `classify`, `review`, or `completed`;
  booleans, nullable strings, and lowercase SHA-256 values have their marked types.
- `diff_analysis` is the untouched initial object: no ready flag, hashes, plan,
  feedback, or approval.
- `classify` requires a recorded diff-summary identity. Its live equality is a
  `record-classification` precondition, while a proven inequality is the
  `invalidate-diff-summary` precondition. On first entry it has no plan identity or
  feedback; after rejection it retains the rejected plan identity plus non-empty user
  feedback; after plan invalidation it has no plan identity plus the fixed invalidation
  feedback. It is never approved.
- `review` requires recorded diff-summary and plan identities, no feedback, and
  `approved: false`. Summary equality is an operation precondition except when a proven
  inequality selects `invalidate-diff-summary`; plan equality is an
  `approve-plan`/`reject-plan` precondition, while a proven inequality is the
  `invalidate-plan` precondition.
- `completed` requires recorded identities for the summary and the fully validated plan,
  no feedback, and `approved: true`. Live equality and continued plan validity are
  `advance-task-phase-to-write` preconditions, not resting invariants: summary drift
  selects `invalidate-diff-summary`, and plan drift selects `invalidate-plan`.
- Every plan entry has a required type. Top-level types are exactly the six
  `top-level-*` values in `plan/classify.md` at tier 1; `adr` is tier 1,
  `module-overview` is tier 1, and `index` is tier 6. The plan's `docsRoot` must
  exactly equal task state, while each plan path is relative to that root.
- `task-state.currentPhase` remains `plan` through all plan-step operations. Only
  `advance-task-phase-to-write` may change it, and only to `write` with the exact
  approved `planFile`.

No same-step mutation is legal except the idempotent task-phase retry described
above. A stale required hash or wrong edge returns `UPDATE_REFUSED: <reason>` with both
prior state files byte-identical. The exceptions are the named invalidation edges, whose
required mismatch is their evidence. A retained rejected-plan hash becoming non-current
during `classify` is candidate production, not a same-step state mutation.

### Report Format

```
RESULT: <updated|error>
OPERATION: <name>
FROM_STEP: <step>
NEW_STEP: <step value if changed>
ERROR: <error message if any>
```

## Important

- Manage `plan-state.json` and `task-state.json` (phase transitions only)
- Do not execute phase work; validate its artifacts and perform only the named state
  operations above.
- Never accept arbitrary fields or caller-selected target states.
