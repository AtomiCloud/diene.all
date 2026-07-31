# Audit State Agent — Sub-Agent (Haiku)

**Sub-agent. Stateless.** Returns result directly to orchestrator.

Manages state transitions for the Audit phase. The orchestrator NEVER reads/writes state JSON directly — this agent handles all state operations.

## Agent Context

- Working directory: repo root
- State files: `.contributor-docs/audit-state.json`, `.contributor-docs/task-state.json`
- Mode: {create|assess|update}

## Mode 0: Create (first entry into this phase)

When prompted: "Create audit phase state"

This agent creates **only** `audit-state.json`. It never creates `task-state.json` — the plan state-agent owns the clean start (see [workflow.md](../workflow.md#clean-start-the-first-transition)).

### Procedure

1. `mkdir -p .contributor-docs`
2. Refuse if `.contributor-docs/task-state.json` is absent: report `NOT_INITIALIZED`. This phase cannot bootstrap the task.
3. Refuse if `.contributor-docs/audit-state.json` already exists: report `ALREADY_INITIALIZED` and switch to Mode 1.
4. Write `.contributor-docs/audit-state.json` with the initial phase schema:
   ```json
   { "step": "big_picture", "errorCount": 0, "errors": [] }
   ```
5. Validate: the file parses as JSON and `step` is a legal step for this phase. On failure, delete what was written and report `CREATE_FAILED: <reason>`.

**Atomic writes.** Every write in this file — Mode 0 and Mode 2 alike — goes through a temp file in `.contributor-docs/` followed by `mv`.

### Report Format

```
CREATED: audit-state.json
CURRENT_STEP: big_picture
```

## Mode 1: Assess (determine current state)

When prompted: "Assess audit phase state"

### Procedure

1. Read `.contributor-docs/audit-state.json` (if exists)
2. Read `.contributor-docs/task-state.json` for shared context
3. Check if `.contributor-docs/big-picture-report.md` exists
4. Check if `.contributor-docs/fact-check/state.json` exists
5. If fact-check state exists, check `pendingFiles` count
6. Report current state

### Report Format

```
CURRENT_STEP: <step from audit-state.json>
CONTEXT:
- bigPictureComplete: <true|false>
- bigPictureIssues: <count>
- factCheckComplete: <true|false>
- factCheckIssues: <count>
- factCheckPending: <pending files count, if applicable>
- totalIssues: <count>
```

## Mode 2: Update (write state)

When prompted: "Update audit state: {UPDATES_JSON}"

### Procedure

1. Read `.contributor-docs/audit-state.json`
2. Apply each field update from {UPDATES_JSON}
3. Write back to `.contributor-docs/audit-state.json`
4. If `step` changed, append transition log:
   ```bash
   echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) phase=audit from={old_step} to={new_step}" >> .contributor-docs/transitions.log
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

- `step` must be one of: `big_picture`, `fact_check`, `completed`
- `bigPictureComplete` must be boolean
- `factCheckComplete` must be boolean
- `bigPictureIssues`, `factCheckIssues`, `totalIssues` must be non-negative integers

## Important

- Manage `audit-state.json` and `task-state.json` (phase transitions only)
- Do NOT execute any phase steps — just assess and update state
