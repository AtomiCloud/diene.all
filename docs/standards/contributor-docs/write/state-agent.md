# Write State Agent — Sub-Agent (Haiku)

**Sub-agent. Stateless.** Returns result directly to orchestrator.

Manages state transitions for the Write phase. The orchestrator NEVER reads/writes state JSON directly — this agent handles all state operations.

## Agent Context

- Working directory: repo root
- State files: `.contributor-docs/write-state.json`, `.contributor-docs/task-state.json`;
  read-only source binding from `.contributor-docs/plan-state.json` and repair evidence
  from `.contributor-docs/audit-state.json`
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
3. Apply the canonical source-snapshot validation in
   `docs/standards/contributor-docs/workflow.md`. On any mismatch report
   `SOURCE_DRIFT_BLOCKED` with the exact evidence and create nothing.
4. Refuse if `.contributor-docs/write-state.json` already exists: report `ALREADY_INITIALIZED` and switch to Mode 1.
5. Write `.contributor-docs/write-state.json` with the initial phase schema — all
   thirteen canonical fields, mirroring
   `docs/standards/contributor-docs/write/PHASE.md`:

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
     "auditRepair": null,
     "gapTransition": null,
     "gapsResolved": []
   }
   ```

6. Validate every field before reporting success, not just parseability:
   - the file parses as JSON;
   - `step` ∈ `scaffold|scaffold_blocked|scaffold_prepared|write_tier_1|write_tier_2|write_tier_3|write_tier_4|write_tier_5|write_tier_6|completed`;
   - `scaffoldComplete` is a boolean;
   - `currentTier` is an integer 0–6;
   - `tiersCompleted` is an array of integers;
   - `filesWritten` and `filesTotal` are non-negative integers;
   - `writeQueue` is an array of strings;
   - `provenance` is an object;
   - `approvedOverwrites` and `blockedCollisions` are valid record arrays (Mode 2);
   - `auditRepair` is null or a valid epoch-bound repair record (Mode 2);
   - `gapTransition` is `null` or a valid transition object (see Mode 3);
   - `gapsResolved` is an array;
   - no field outside this set is present.

   On any failure, delete what was written and report `CREATE_FAILED: <reason>`.

**Atomic writes.** Every write in this file — Modes 0, 2 and 3 alike — goes through a
temp file in `.contributor-docs/` followed by `mv`. Every Mode 3 edge is individually
atomic, and `gapTransition` is the commit marker for the multi-edge operation: its
recorded `status` says exactly which effects already landed, so an interrupted
transition is resumed rather than guessed at. This is the same
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

1. Read `.contributor-docs/write-state.json` (if exists).
2. Read `.contributor-docs/task-state.json` for shared context.
3. Validate the diff summary's source snapshot with the canonical workflow procedure,
   including its fresh equality to `plan-state.json.diffSummaryHash`. Derive
   `sourceSnapshotCurrent` and exact binding/drift evidence. A false result blocks
   every dispatch, including recovery, without changing state.
4. Check which `.contributor-docs/write-tier-N/state.json` files exist.
5. For existing tier states, check `pendingFiles` count.
6. Report current state.

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
- sourceSnapshotCurrent: <true|false>
- sourceSnapshotMismatch: <none | summary binding, identity/digest mismatch, or sorted outside dirty paths>
- currentTier: <number>
- tiersCompleted: <list>
- filesWritten: <count of provenance entries with writeStatus == "written">
- filesTotal: <count>
- queueLength: <writeQueue.length>
- blockedCollisions: <count>
- unconsumedApprovals: <count>
- auditRepair: <none | auditEpoch/status/paths>
- gapTransition: <none | enqueued | planned | prepared | scaffolded | reset | cleaned>
- pendingInTier: <queued paths in currentTier with writeStatus == "pending">
- tierPending: <pending files in current tier's processor state, if applicable>
```

`gapTransition` is reported first among the derived lines when it is not `none`,
because a non-null transition outranks the step: the orchestrator must finish it
before dispatching any tier.

When processor state says a path is pending but canonical provenance says `written`,
assessment reports it under `PROCESSOR_RECONCILE` only after a fresh disk hash equals
`writtenHash`. A mismatch is `WRITTEN_BYTES_CHANGED` and blocks dispatch.

## Mode 2: Commanded Write-State Operations

When prompted: `Update write state: {OPERATION_JSON}`

`OPERATION_JSON` must name exactly one operation below. A generic field patch is
refused with `UPDATE_REFUSED: operation required`; callers cannot manufacture a step
or counter by supplying its desired value.

### Universal Procedure

1. Read and completely validate write and task state. For either audit-repair
   operation, also validate audit state and every cited current artifact.
2. Validate the canonical source snapshot. On any mismatch report
   `SOURCE_DRIFT_BLOCKED` and leave state and processor artifacts byte-identical.
3. Refuse Mode 2 while `gapTransition != null`; Mode 3 exclusively owns that graph.
4. Validate every path as normalized, root-relative, and contained by `docsRoot`.
5. Build the operation's complete candidate object, derive both counters, and enforce
   the source step, target step, and target invariants below.
6. Validate before writing, then use a temp file plus atomic rename.
7. When the step changes, append the transition only after the rename.

### Legal Operations

| Operation                     | Legal source        | Required validation and atomic effect                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| ----------------------------- | ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `prepare-scaffold`            | `scaffold`          | Validate a whole-plan, exact-byte manifest and its hashes. Persist writable queue/provenance with `scaffoldedAt: null`, measure every collision, derive totals, then move to `scaffold_blocked` or `scaffold_prepared`. No target file may have been written.                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `resolve-scaffold`            | `scaffold_blocked`  | Require approve/skip for the exact blocked set. Freshly match every approval to `observedHash`; append hash-bound scaffold approvals, update queue/provenance, clear only resolved collisions, derive totals, and reach `scaffold_prepared` only when none remain.                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `block-scaffold`              | `scaffold_prepared` | Freshly measure a create-time collision, record its exact current/expected hashes, and move to `scaffold_blocked`. Prepared hashes and already-created matching files remain adoptable.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `finalize-scaffold`           | `scaffold_prepared` | Require zero collisions and freshly hash every queued file to its prepared `scaffoldHash`; fill null `scaffoldedAt`, consume used scaffold approvals, set `scaffoldComplete: true`, derive counters, and move to `write_tier_1`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `reopen-audit-repair`         | `completed`         | Require task/audit failure with nonzero current stamped errors, an existing marker that is null or older than the current audit epoch, and a non-empty exact set of queued paths named by those errors. Validate the completed resting state without requiring live hashes, then measure mismatches as collisions. Remove and verify absent every processor state/findings tree from the lowest selected tier through 6. Atomically install the current epoch-bound `auditRepair: replaying` marker, restore only those paths to pending while retaining `writtenHash`, truncate tier completion, derive counters, and enter the lowest selected tier. After that rename, move task phase `failed → write`. |
| `resume-audit-repair-phase`   | `write_tier_N`      | Crash reconciliation for the prior operation: require task phase still `failed`, audit step `failed`, and at least one pending path that retains a `writtenHash` and is named by current stamped errors. A collided path still satisfies this retained-provenance test. Require the matching `auditRepair: replaying` marker, then update only task phase to `write`.                                                                                                                                                                                                                                                                                                                                       |
| `record-writer-collision`     | `write_tier_N`      | Freshly hash one pending path that differs from its retained normal authority, atomically replace that path's collision record with exact observed/expected hashes, and keep the tier step. Any nonempty collision set blocks dispatch.                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `approve-writer-replay`       | `write_tier_N`      | Require an existing collision and an explicit user decision, freshly match `observedHash`, append an unconsumed `purpose: "writer-replay"` approval, and remove that collision atomically. A changed path is remeasured and remains blocked.                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `record-write`                | `write_tier_N`      | Require the path in the current tier, pending status, a report carrying valid `AUTHORIZED_FROM_HASH` and `WRITTEN_HASH`, and a legal start authorization. Freshly hash disk to `WRITTEN_HASH`, then atomically record written status/hash, derive `filesWritten`, and consume the exact replay approval if one authorized it.                                                                                                                                                                                                                                                                                                                                                                               |
| `complete-tier`               | `write_tier_N`      | Require zero collisions, the processor empty, every tier path written, and every fresh disk hash equal to `writtenHash`. Append N once. Advance to tier N+1, or keep `currentTier: 6` and reach `completed` after tier 6.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `advance-task-phase-to-audit` | `completed`         | Require the complete-step invariants and fresh live hashes. On the initial write, atomically update task phase `write → audit`. During repair, require the matching `auditRepair: replaying` marker and failed audit, freshly verify every marked path, atomically set the marker to `completed`, then update task phase `write → audit`. A retry that sees the completed marker with task phase still `write` finishes only the second rename.                                                                                                                                                                                                                                                             |

`record-write` accepts a start authorization only when
`AUTHORIZED_FROM_HASH` equals the first-write `scaffoldHash`, the retained replay
`writtenHash`, or the `approvedHash` of one unconsumed writer-replay approval for the
same path. An approval does not mutate `writtenHash` and cannot be selected twice.
The writer performs the same fresh pre-write check; the state-agent independently
checks the returned bytes before completion.

`reopen-audit-repair` never blesses changed bytes. Its `completed` source invariant
requires all queue entries to be written but deliberately does not require live hashes;
the operation performs that fresh comparison itself. A selected file that still hashes
to its retained `writtenHash` can replay normally. Any mismatch becomes an exact
collision in the reopened tier and blocks every writer until
`approve-writer-replay` records a fresh one-use decision. Cleanup happens before the
state rename: a crash after cleanup but before reopening merely discards processor
caches and safely repeats; a crash after reopening but before the task-phase rename is
reconciled only by `resume-audit-repair-phase`.

### Step Invariants

- `scaffold`: initial empty queue/provenance/approval/collision state, false complete
  flag, tier 0, and zero counters.
- `scaffold_blocked`: false complete flag and at least one valid collision record.
- `scaffold_prepared`: false complete flag, no collisions, exact queue/provenance
  key equality, and every prepared entry has `scaffoldedAt: null`.
- `write_tier_N`: true complete flag, every provenance entry has a non-null
  `scaffoldedAt`, `currentTier == N`, and `tiersCompleted == [1..N-1]`. A nonempty
  collision set is a valid blocked subtype but forbids writer dispatch and tier
  completion.
- `completed`: tiers exactly `[1, 2, 3, 4, 5, 6]`, tier 6, every queue entry written,
  and `filesWritten == filesTotal`. Live-hash equality is an operation precondition for
  `complete-tier`, `advance-task-phase-to-audit`, and audit reset; it is not a resting
  invariant, so `reopen-audit-repair` can measure drift into collisions.

No operation may skip a source step, fabricate `tiersCompleted`, or enter completed
state with pending work. A same-step update not named above is also refused.

### Complete-Object Validation

- The object has exactly the canonical thirteen keys and a legal ten-value `step`.
- `scaffoldComplete` is boolean; `currentTier` is an integer 0–6;
  `tiersCompleted` is a sorted, duplicate-free integer array.
- Both counters are non-negative integers; `filesTotal == writeQueue.length` and
  `filesWritten` equals the number of written provenance entries.
- `writeQueue` contains unique, normalized strings under `docsRoot`; its set equals
  the provenance key set.
- Every provenance value has exactly the six fields below. `scaffoldHash` and every
  non-null `writtenHash` are lowercase SHA-256 values; `scaffoldedAt` is null only in
  a scaffold preparation step; written status requires a non-null `writtenHash`.
- Approval and collision entries have exactly the marked shapes below. Approval
  timestamps are valid, `consumedAt` is null or a valid timestamp, and a collision's
  hashes, tier, count, and path are valid. At most one unconsumed approval may exist
  for a path and purpose, and a new approval requires that path's current collision
  record.
- `auditRepair` is null or has exactly the four mirrored fields below: a positive
  integer epoch, lowercase SHA-256 digest, non-empty unique normalized queued paths,
  and status `replaying|completed`. A current `replaying` record is legal only during
  its reopened tiers or their completed/task-`write` handoff; `completed` requires
  write step `completed` and every marked path written. A marker older than the audit
  epoch is inert and may be replaced only by `reopen-audit-repair` for the newer failed
  epoch. A marker equal to or newer than the current audit epoch is never replaceable;
  a future-epoch marker is invalid.
- `gapTransition` is null in this mode; `gapsResolved` contains only Mode 3 closed
  records with `status: "cleared"`.
- `reopen-audit-repair` additionally validates the current audit epoch/digest stamps;
  each fact-check finding also needs its current per-file hash, while a big-picture
  report is bound by the live whole-tree digest. Each selected path is named by at
  least one current error, is already queued with written provenance, and appears
  once. It never accepts a warning-only or caller-invented path.
- Unknown fields in any object are refused, never merged.

### Canonical Record Mirrors

<!-- canonical-block: write-provenance-record -->

```json
{
  "docs/contributor/orders/features/checkout.mdx": {
    "origin": "new | run-owned-scaffold | approved-overwrite",
    "scaffoldHash": "<sha256 of the exact prepared scaffold bytes>",
    "scaffoldedAt": "<ISO-8601 or null while prepared>",
    "tier": 4,
    "writeStatus": "pending | written",
    "writtenHash": null
  }
}
```

<!-- canonical-block: write-approval-record -->

```json
{
  "path": "docs/contributor/orders/features/checkout.mdx",
  "approvedHash": "<sha256 of the exact bytes the user approved replacing>",
  "purpose": "scaffold | writer-replay",
  "approvedAt": "<ISO-8601>",
  "consumedAt": null
}
```

<!-- canonical-block: write-collision-record -->

```json
{
  "path": "docs/contributor/orders/features/checkout.mdx",
  "observedHash": "<sha256 of the current bytes>",
  "expectedHash": "<sha256 of the normal scaffold or replay authority>",
  "tier": 4,
  "lineCount": 83,
  "detectedAt": "<ISO-8601>"
}
```

<!-- canonical-block: write-audit-repair-record -->

```json
{
  "auditEpoch": 1,
  "docsDigest": "39e77a6619ba41e414906e08eb0f1d62d3069469c2b7cd5f702058869f256fb9",
  "paths": ["docs/contributor/orders/features/checkout.mdx"],
  "status": "replaying | completed"
}
```

### Report Format

```text
RESULT: <updated|refused>
OPERATION: <name>
FROM_STEP: <step>
NEW_STEP: <step>
FILES_WRITTEN: <derived count>
ERROR: <reason if refused>
```

## Mode 3: Gap (the discovered-gap transition)

When prompted: `Gap operation: {OPERATION_JSON}`

This mode exclusively enforces the complete graph:

`enqueued → planned → prepared → scaffolded → reset → cleaned → cleared`

There is no arbitrary status update. Each edge is a named operation, and the agent
verifies the edge's durable filesystem or plan effect before atomically recording its
target. A skipped, reversed, or fabricated edge is `GAP_TRANSITION_INVALID`.
Before any edge or collision decision, validate the canonical source snapshot. A
mismatch is `SOURCE_DRIFT_BLOCKED` and leaves the entire transition byte-identical.

### The transition record

<!-- canonical-block: gap-transition-record -->

```json
{
  "status": "enqueued | planned | prepared | scaffolded | reset | cleaned",
  "reports": [
    {
      "reportedBy": "docs/contributor/orders/features/checkout.mdx",
      "gaps": [
        {
          "path": "docs/contributor/orders/concepts/idempotency.mdx",
          "reason": "Checkout needs the shared idempotency contract"
        }
      ]
    }
  ],
  "gapPaths": [
    {
      "path": "docs/contributor/orders/concepts/idempotency.mdx",
      "type": "concept",
      "tier": 2
    }
  ],
  "expectedScaffold": {
    "docs/contributor/orders/concepts/idempotency.mdx": "<sha256>"
  },
  "replayTier": 2,
  "requeued": ["docs/contributor/orders/features/checkout.mdx"],
  "resetTiers": [2, 4],
  "cleanedTiers": [],
  "openedAt": "<ISO-8601>"
}
```

### Sub-operation `open`

Collect the complete tier batch before calling. Validate a non-empty, duplicate-free
`reports` array; every reporter must be a normalized queued path in the current tier,
every nested gap must have a non-empty reason, and the normalized nested path union
must exactly equal `gapPaths`. Validate gap
path containment under `docsRoot`, concept/algorithm type-to-tier rules, no current
queue member, the loop guard, and the independently recomputed `requeued`,
`replayTier`, and `resetTiers` values. `replayTier` may not exceed `currentTier`.

One atomic write installs `status: "enqueued"`, the exact reports and computed values,
empty `expectedScaffold`/`cleanedTiers`, and `openedAt`. No ordinary write-state field
changes.

### Sub-operation `plan`

Legal only from `enqueued`. Read `doc-plan.yaml` and verify every gap entry exists with
the recorded normalized path, type, and tier. For each element of `reports`, verify
that reporter's plan `crossLinks` now contains every nested gap path in that report.
Only then
atomically set `status: "planned"`. The agent validates these plan edits but never
authors them.

### Sub-operation `prepare`

Legal only from `planned`. Accept the scaffolder's machine-readable exact-byte
manifest, recompute every hash, and require its path set to equal `gapPaths` exactly.
`expectedScaffold` therefore has neither missing nor extra keys and every value is a
lowercase SHA-256.

On a target's first planned→prepared observation, any existing bytes are a collision —
even when they equal the proposal — because no prepared record existed before that
observation. Measure them into `blockedCollisions` and remain planned. On a later
attempt, a target whose fresh hash still equals one unconsumed `purpose: "scaffold"`
approval is resolved rather than measured again; any changed or unapproved target is
blocked. A required gap cannot be skipped. Once no collision is unresolved, atomically
install exact `expectedScaffold` key coverage and set `status: "prepared"`. No doc file
may be written before that rename.

### Sub-operation `approve-collision`

Legal while status is `planned` or `prepared` and a gap collision is recorded. Require
an explicit per-path user approval, freshly match the current bytes to `observedHash`,
and atomically append an unconsumed `purpose: "scaffold"` approval while removing only
that collision. A changed hash is remeasured and remains blocked. `skip` is refused
because every gap path is a required dependency; abandoning it requires failing the
workflow rather than clearing recovery state.

### Sub-operation `scaffold`

Legal only from `prepared`. The scaffolder re-renders exact bytes and must match every
persisted expected hash. At this status, a current file already hashing to
`expectedScaffold[path]` is explicitly adoptable: it is the durable signature of a
create that finished before the state edge was recorded. An absent target may be
created; an exact unconsumed scaffold approval may be overwritten. Any other current
hash is recorded as `GAP_COLLISION`, and status remains prepared.

After create/adopt returns, freshly require every target to equal its expected hash.
In one atomic write extend `writeQueue`, install provenance using `origin: "new"` or
`approved-overwrite` as measured, set non-null `scaffoldedAt`, consume used approvals,
derive both counters, clear resolved collisions, and set `status: "scaffolded"`.

### Sub-operation `apply`

One atomic write, legal only when `status == "scaffolded"`; otherwise report
`GAP_TRANSITION_INVALID`. It performs, together:

1. `tiersCompleted` truncated to the tiers strictly less than `replayTier`
2. `currentTier: replayTier` and `step: "write_tier_<replayTier>"`
3. every path in `requeued` set to `writeStatus: "pending"`, **keeping** its
   `writtenHash` — that retained hash is the authorization the replaying writer checks
4. `filesWritten` recomputed from provenance
5. `status: "reset"`

The state rename commits every effect together. A retry that observes `status: "reset"`
reports `GAP: applied` without rewriting; a retry that still observes `scaffolded`
applies the edge once.

### Sub-operation `clean`

Legal only from `reset`. Select the first `resetTiers` member absent from
`cleanedTiers`. Remove its exact processor `state.json` and findings tree, then verify
both are absent. Only after that verification does one atomic state write append the
tier. When the sorted, unique `cleanedTiers` set equals `resetTiers`, the same write
sets `status: "cleaned"`. A failed removal reports `GAP_CLEANUP_INCOMPLETE` and changes
no state. Missing artifacts are already absent, so retries are idempotent.

### Sub-operation `clear`

One atomic write, legal only when `status == "cleaned"`; otherwise report
`GAP_CLEANUP_INCOMPLETE`. **Refuse to clear while `cleanedTiers` does not cover
`resetTiers`.** Clearing early would leave a completed-looking processor state on disk
for a tier that now has pending work, and the tier initializer would skip the replayed
files while every counter reported success.

`clear` appends a copy with `status: "cleared"` plus `closedAt` to `gapsResolved` and
sets `gapTransition: null`. The append is idempotent by `openedAt`: if
`gapsResolved` already holds a closed entry with this `openedAt`, do not append a
second one.

### Report Format

```text
GAP: <opened|planned|prepared|scaffolded|applied|cleaned|cleared|refused>
STATUS: <status after this operation>
REPLAY_TIER: <n>
REPORTERS: <count>
GAP_PATHS: <count>
REQUEUED: <count>
RESET_TIERS: <list>
ERROR: <named refusal, if any>
```

### Gap Validation and Refusals

- The live record has exactly the nine marked fields. `reports` is non-empty, each
  nested gap retains a non-empty reason, and its path union equals `gapPaths`; every
  reporter and gap path passes containment and membership checks.
- `expectedScaffold` is empty at enqueued/planned and has exact gap-path key coverage
  at prepared and later statuses.
- `cleanedTiers` is always a duplicate-free subset of `resetTiers`; cleaned requires
  exact equality and verified artifact absence.
- `gapsResolved` records have the same core fields plus `closedAt`, and status exactly
  `cleared`.
- `GAP_IN_FLIGHT`, `GAP_REPORTER_INVALID`, `GAP_REPORT_SET_INVALID`,
  `GAP_PATH_INVALID`, `GAP_ALREADY_QUEUED`, `GAP_LOOP`, `GAP_TIER_INVALID`,
  `GAP_MANIFEST_INVALID`, `GAP_COLLISION`, `GAP_TRANSITION_INVALID`, and
  `GAP_CLEANUP_INCOMPLETE` leave the prior state byte-identical except that a
  collision-measurement operation may atomically replace `blockedCollisions` with the
  freshly measured exact records while retaining the same status.

## Important

- Manage `write-state.json` and `task-state.json` (phase transitions only)
- Do not plan or write documentation content.
- Mode 3 validates plan/scaffold effects and owns deletion of reset processor state;
  the orchestrator authors plan edits and the scaffolder authors scaffold bytes.
- Mode 2 owns write-tier processor cleanup for `reopen-audit-repair`; documentation
  fixes themselves still run through doc-writers and `record-write`.
- Never accept a caller-supplied status without executing its named edge operation.
