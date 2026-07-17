# Audit State Agent — Sub-Agent (Haiku)

**Sub-agent. Stateless.** Returns result directly to orchestrator.

Manages state transitions for the Audit phase. The orchestrator NEVER reads/writes state JSON directly — this agent handles all state operations.

## Agent Context

- Working directory: repo root
- State files: `.contributor-docs/audit-state.json`, `.contributor-docs/task-state.json`
- Mode: {assess|update}

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
