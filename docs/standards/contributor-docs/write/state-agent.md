# Write State Agent — Sub-Agent (Haiku)

**Sub-agent. Stateless.** Returns result directly to orchestrator.

Manages state transitions for the Write phase. The orchestrator NEVER reads/writes state JSON directly — this agent handles all state operations.

## Agent Context

- Working directory: repo root
- State files: `.contributor-docs/write-state.json`, `.contributor-docs/task-state.json`
- Mode: {create|assess|update}

## Mode 0: Create (first entry into this phase)

When prompted: "Create write phase state"

This agent creates **only** `write-state.json`. It never creates `task-state.json` — the plan state-agent owns the clean start (see [workflow.md](../workflow.md#clean-start-the-first-transition)).

### Procedure

1. `mkdir -p .contributor-docs`
2. Refuse if `.contributor-docs/task-state.json` is absent: report `NOT_INITIALIZED`. This phase cannot bootstrap the task.
3. Refuse if `.contributor-docs/write-state.json` already exists: report `ALREADY_INITIALIZED` and switch to Mode 1.
4. Write `.contributor-docs/write-state.json` with the initial phase schema:
   ```json
   { "step": "scaffold", "completedTiers": [], "errors": [] }
   ```
5. Validate: the file parses as JSON and `step` is a legal step for this phase. On failure, delete what was written and report `CREATE_FAILED: <reason>`.

**Atomic writes.** Every write in this file — Mode 0 and Mode 2 alike — goes through a temp file in `.contributor-docs/` followed by `mv`.

### Report Format

```
CREATED: write-state.json
CURRENT_STEP: scaffold
```

## Mode 1: Assess (determine current state)

When prompted: "Assess write phase state"

### Procedure

1. Read `.contributor-docs/write-state.json` (if exists)
2. Read `.contributor-docs/task-state.json` for shared context
3. Read `.contributor-docs/doc-plan.yaml` for file counts per tier
4. Check which `.contributor-docs/write-tier-N/state.json` files exist
5. For existing tier states, check `pendingFiles` count
6. Report current state

### Report Format

```
CURRENT_STEP: <step from write-state.json>
CONTEXT:
- scaffoldComplete: <true|false>
- currentTier: <number>
- tiersCompleted: <list>
- filesWritten: <count>
- filesTotal: <count>
- tierPending: <pending files in current tier, if applicable>
```

## Mode 2: Update (write state)

When prompted: "Update write state: {UPDATES_JSON}"

### Procedure

1. Read `.contributor-docs/write-state.json`
2. Apply each field update from {UPDATES_JSON}
3. Write back to `.contributor-docs/write-state.json`
4. If `step` changed, append transition log:
   ```bash
   echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) phase=write from={old_step} to={new_step}" >> .contributor-docs/transitions.log
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

- `step` must be one of: `scaffold`, `write_tier_1`, `write_tier_2`, `write_tier_3`, `write_tier_4`, `write_tier_5`, `write_tier_6`, `completed`
- `scaffoldComplete` must be boolean
- `currentTier` must be 0-6
- `tiersCompleted` must be an array of integers
- `filesWritten` and `filesTotal` must be non-negative integers

## Important

- Manage `write-state.json` and `task-state.json` (phase transitions only)
- Do NOT execute any phase steps — just assess and update state
