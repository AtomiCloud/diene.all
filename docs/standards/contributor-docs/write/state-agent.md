# Write State Agent — Sub-Agent (Haiku)

**Sub-agent. Stateless.** Returns result directly to orchestrator.

Manages state transitions for the Write phase. The orchestrator NEVER reads/writes state JSON directly — this agent handles all state operations.

## Agent Context

- Working directory: repo root
- State files: `.contributor-docs/write-state.json`, `.contributor-docs/task-state.json`
- Mode: {create|assess|update|gap}

The canonical schema is `docs/standards/contributor-docs/write/PHASE.md`. Every field
list, step list and record shape below mirrors it exactly; if they ever disagree,
PHASE.md is authoritative and the drift is repaired here.

## Mode 0: Create (first entry into this phase)

When prompted: "Create write phase state"

This agent creates **only** `write-state.json`. It never creates `task-state.json` — the plan state-agent owns the clean start (see [workflow.md](../workflow.md#clean-start-the-first-transition)).

### Procedure

1. `mkdir -p .contributor-docs`
2. Refuse if `.contributor-docs/task-state.json` is absent: report `NOT_INITIALIZED`. This phase cannot bootstrap the task.
3. Refuse if `.contributor-docs/write-state.json` already exists: report `ALREADY_INITIALIZED` and switch to Mode 1.
4. Write `.contributor-docs/write-state.json` with the initial phase schema — all
   twelve canonical fields, mirroring `docs/standards/contributor-docs/write/PHASE.md`:

   <!-- canonical-block: write-state-schema -->

   ```json
   {
     "step": "scaffold",
     "scaffoldComplete": false,
     "currentTier": 0,
     "tiersCompleted": [],
     "filesWritten": 0,
     "filesTotal": 0,
     "writeQueue": [],
     "provenance": {},
     "approvedOverwrites": [],
     "blockedCollisions": [],
     "gapTransition": null,
     "gapsResolved": []
   }
   ```

5. Validate every field before reporting success, not just parseability:
   - the file parses as JSON;
   - `step` ∈ `scaffold|gap_scaffold|write_tier_1|write_tier_2|write_tier_3|write_tier_4|write_tier_5|write_tier_6|completed`;
   - `scaffoldComplete` is a boolean;
   - `currentTier` is an integer 0–6;
   - `tiersCompleted` is an array of integers;
   - `filesWritten` and `filesTotal` are non-negative integers;
   - `writeQueue` is an array of strings;
   - `provenance` is an object;
   - `approvedOverwrites` and `blockedCollisions` are arrays;
   - `gapTransition` is `null` or a valid transition object (see Mode 3);
   - `gapsResolved` is an array;
   - no field outside this set is present.

   On any failure, delete what was written and report `CREATE_FAILED: <reason>`.

**Atomic writes.** Every write in this file — Modes 0, 2 and 3 alike — goes through a
temp file in `.contributor-docs/` followed by `mv`. Mode 3's two writes are each
individually atomic, and `gapTransition` is the commit marker that makes the pair
recoverable: its recorded `status` says exactly which effects already landed, so an
interrupted transition is resumed rather than guessed at. This is the same
commit-marker discipline the plan state-agent uses for the two-file clean start
(`docs/standards/contributor-docs/plan/state-agent.md`).

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
3. Check which `.contributor-docs/write-tier-N/state.json` files exist
4. For existing tier states, check `pendingFiles` count
5. Report current state

**Counts come from `writeQueue` and `provenance`, never from `doc-plan.yaml`.** The
plan lists what was wanted; the queue records what was approved. Re-deriving per-tier
counts from the plan reintroduces every path the collision step refused, which is the
re-derivation `docs/standards/contributor-docs/write/PHASE.md` forbids — so this mode
does not read the plan at all.

### Report Format

```
CURRENT_STEP: <step from write-state.json>
CONTEXT:
- scaffoldComplete: <true|false>
- currentTier: <number>
- tiersCompleted: <list>
- filesWritten: <count of provenance entries with writeStatus == "written">
- filesTotal: <count>
- queueLength: <writeQueue.length>
- gapTransition: <none | enqueued | planned | prepared | scaffolded | reset | cleaned>
- pendingInTier: <queued paths in currentTier with writeStatus == "pending">
- tierPending: <pending files in current tier's processor state, if applicable>
```

`gapTransition` is reported first among the derived lines when it is not `none`,
because a non-null transition outranks the step: the orchestrator must finish it
before dispatching any tier.

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

- `step` must be one of: `scaffold`, `gap_scaffold`, `write_tier_1`, `write_tier_2`, `write_tier_3`, `write_tier_4`, `write_tier_5`, `write_tier_6`, `completed`
- `scaffoldComplete` must be boolean
- `currentTier` must be 0-6
- `tiersCompleted` must be an array of integers
- `filesWritten` and `filesTotal` must be non-negative integers
- `filesWritten` must equal the number of `provenance` entries with `writeStatus == "written"` — it is derived, never incremented
- `writeQueue` must be an array of strings
- `approvedOverwrites` and `blockedCollisions` must be arrays of strings
- `gapTransition` must be `null` or a valid transition object (Mode 3)
- `gapsResolved` must be an array of closed transition records
- **Provenance integrity:** every `provenance` key must be a `writeQueue` member and every `writeQueue` member must have a `provenance` entry. A queue entry with no provenance is exactly the condition the doc-writer refuses on (`docs/standards/contributor-docs/write/write-file.md`), so this agent must never be able to create one.
- Each `provenance` value must carry exactly `origin`, `scaffoldHash`, `scaffoldedAt`, `tier`, `writeStatus`, `writtenHash`, with `writeStatus` ∈ `pending|written`, `tier` an integer 1–6, and `writtenHash` a sha256 string or `null`
- `writtenHash` must be non-null whenever `writeStatus == "written"`
- **Unknown fields are rejected, never merged.** An update naming a field outside the canonical twelve is a caller bug: refuse it and report `UNKNOWN_FIELD: <name>` rather than writing a state file that no longer matches the schema. Silent merging is how the drift this contract exists to prevent got in.

### Provenance Record

Every `provenance` value has exactly this shape, mirroring
`docs/standards/contributor-docs/write/PHASE.md`:

<!-- canonical-block: write-provenance-record -->

```json
{
  "docs/contributor/orders/features/checkout.mdx": {
    "origin": "new | run-owned-scaffold | approved-overwrite",
    "scaffoldHash": "<sha256 of the exact bytes this run scaffolded>",
    "scaffoldedAt": "<ISO-8601>",
    "tier": 4,
    "writeStatus": "pending | written",
    "writtenHash": null
  }
}
```

`writtenHash` is set — together with `writeStatus: "written"` — in the same update that
records a completed write. A replay clears `writeStatus` back to `pending` but never
clears `writtenHash`, because the retained hash is what proves the bytes on disk are
still the ones this workflow wrote and may therefore be replaced. Pending status alone
proves nothing.

## Mode 3: Gap (the discovered-gap transition)

When prompted: "Open gap transition: {GAP_JSON}" or "Advance gap transition: {STATUS}"

This mode owns the two durable state writes of the transition whose mechanism is
defined in
`docs/standards/contributor-docs/write/PHASE.md` — the opening write and the reset
write. The intermediate statuses (`planned`, `prepared`, `scaffolded`, `cleaned`) are
recorded by this agent on the orchestrator's instruction as single-field updates. This
agent never re-plans, never scaffolds, and never deletes processor state itself.

### The transition record

<!-- canonical-block: gap-transition-record -->

```json
{
  "status": "enqueued | planned | prepared | scaffolded | reset | cleaned",
  "reportedBy": "docs/contributor/orders/features/checkout.mdx",
  "gapPaths": [
    {
      "path": "docs/contributor/orders/concepts/idempotency.mdx",
      "type": "concept",
      "tier": 2
    }
  ],
  "expectedScaffold": {},
  "replayTier": 2,
  "requeued": ["docs/contributor/orders/features/checkout.mdx"],
  "resetTiers": [2, 4],
  "cleanedTiers": [],
  "openedAt": "<ISO-8601>"
}
```

### Sub-operation `open`

One atomic write. Sets `gapTransition` to the record above with `status: "enqueued"`,
`expectedScaffold: {}` and `cleanedTiers: []`. Nothing else in the state file changes —
in particular `step`, `currentTier` and `tiersCompleted` are untouched, because the
reset is a separate durable step.

Refusals, checked in this order:

| Condition                                                               | Report               |
| ----------------------------------------------------------------------- | -------------------- |
| `gapTransition != null`                                                 | `GAP_IN_FLIGHT`      |
| A `gapPaths` member is already on `writeQueue`                          | `GAP_ALREADY_QUEUED` |
| A `gapPaths` member appears in two or more prior `gapsResolved` entries | `GAP_LOOP`           |
| `replayTier > currentTier`                                              | `GAP_TIER_INVALID`   |

`GAP_TIER_INVALID` catches a gap that would replay _forward_, which is never a
recovery — the tiers above `currentTier` have not run yet, so there is nothing to
replay into. `GAP_LOOP` is the loop guard: a third report of the same missing path is a
planning failure, not a retry.

### Sub-operation `apply`

One atomic write, legal only when `status == "scaffolded"`; otherwise report
`GAP_NOT_SCAFFOLDED`. It performs, together:

1. `tiersCompleted` truncated to the tiers strictly less than `replayTier`
2. `currentTier: replayTier` and `step: "write_tier_<replayTier>"`
3. every path in `requeued` set to `writeStatus: "pending"`, **keeping** its
   `writtenHash` — that retained hash is the authorization the replaying writer checks
4. `filesWritten` recomputed from provenance
5. `status: "reset"`

Every effect is an assignment to a value already recorded in the transition, so
re-applying an applied reset is a no-op and a crash mid-apply is recovered by simply
applying again.

### Sub-operation `clear`

One atomic write, legal only when `status == "cleaned"`; otherwise report
`GAP_CLEANUP_INCOMPLETE`. **Refuse to clear while `cleanedTiers` does not cover
`resetTiers`.** Clearing early would leave a completed-looking processor state on disk
for a tier that now has pending work, and the tier initializer would skip the replayed
files while every counter reported success.

`clear` appends the record plus `closedAt` to `gapsResolved` and sets
`gapTransition: null`. The append is idempotent by `openedAt`: if `gapsResolved`
already holds an entry with this `openedAt`, do not append a second one.

### Report Format

```
GAP: <opened|advanced|applied|cleared>
STATUS: <status after this operation>
REPLAY_TIER: <n>
GAP_PATHS: <count>
REQUEUED: <count>
RESET_TIERS: <list>
ERROR: <GAP_IN_FLIGHT | GAP_ALREADY_QUEUED | GAP_LOOP | GAP_TIER_INVALID | GAP_NOT_SCAFFOLDED | GAP_CLEANUP_INCOMPLETE, if any>
```

## Important

- Manage `write-state.json` and `task-state.json` (phase transitions only)
- Do NOT execute any phase steps — just assess and update state
- Mode 3 records the transition; it never re-plans, scaffolds, writes doc files, or deletes processor state. Those are the orchestrator's and the scaffolder's steps.
