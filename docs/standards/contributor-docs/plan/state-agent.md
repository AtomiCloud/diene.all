# Plan State Agent — Sub-Agent (Haiku)

**Sub-agent. Stateless.** Returns result directly to orchestrator.

Manages state transitions for the Plan phase. The orchestrator NEVER reads/writes state JSON directly — this agent handles all state operations.

## Agent Context

- Working directory: repo root
- State files: `.contributor-docs/plan-state.json`, `.contributor-docs/task-state.json`
- Mode: {assess|update}

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
   ```json
   {
     "step": "diff_analysis",
     "diffSummaryReady": false,
     "planFile": null,
     "approved": false,
     "reviewFeedback": null
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
   - `step` ∈ `diff_analysis|classify|review`;
   - `diffSummaryReady` and `approved` are booleans;
   - `planFile` and `reviewFeedback` are a string or `null`;
   - `baseBranch` resolves to an existing ref.

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

1. Read `.contributor-docs/plan-state.json` (if exists)
2. Read `.contributor-docs/task-state.json` for shared context
3. Check if `.contributor-docs/diff-summary.md` exists
4. Check if `.contributor-docs/doc-plan.yaml` exists
5. Report current state

### Report Format

```
CURRENT_STEP: <step from plan-state.json>
CONTEXT:
- diffSummaryReady: <true|false>
- planFile: <exists|absent>
- approved: <true|false>
- reviewFeedback: <present|absent>
```

## Mode 2: Update (write state)

When prompted: "Update plan state: {UPDATES_JSON}"

### Procedure

1. Read `.contributor-docs/plan-state.json`
2. Apply each field update from {UPDATES_JSON}
3. Write back to `.contributor-docs/plan-state.json`
4. If `step` changed, append transition log:
   ```bash
   echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) phase=plan from={old_step} to={new_step}" >> .contributor-docs/transitions.log
   ```
5. Report what changed

When prompted to update `task-state.json` (phase transitions only):

1. Read `.contributor-docs/task-state.json`
2. Apply updates
3. Write back
4. Append phase transition log:
   ```bash
   echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) phase-transition from={old} to={new}" >> .contributor-docs/transitions.log
   ```

### Report Format

```
RESULT: <updated|error>
FIELDS_UPDATED: <list>
NEW_STEP: <step value if changed>
ERROR: <error message if any>
```

### Validation Rules

- `step` must be one of: `diff_analysis`, `classify`, `review`, `completed`
- `diffSummaryReady` must be boolean
- `approved` must be boolean
- `planFile` must be a string path or null
- `reviewFeedback` must be a string or null

## Important

- Manage `plan-state.json` and `task-state.json` (phase transitions only)
- Do NOT execute any phase steps — just assess and update state
