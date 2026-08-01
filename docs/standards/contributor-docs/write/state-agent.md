# Write State Agent — Sub-Agent (Haiku)

**Sub-agent. Stateless.** Returns result directly to orchestrator.

Manages state transitions for the Write phase. The orchestrator NEVER reads/writes state JSON directly — this agent handles all state operations.

## Agent Context

- Working directory: repo root
- State files: `.contributor-docs/write-state.json`, `.contributor-docs/task-state.json`;
  read-only approved-plan root/source binding from
  `.contributor-docs/plan-state.json`, exact live bytes from
  `.contributor-docs/doc-plan.yaml`, and repair evidence from
  `.contributor-docs/audit-state.json`
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
4. Read and completely validate the exact seven-field plan state and task state.
   Require plan step `completed`, `approved: true`, `reviewFeedback: null`, non-null
   lowercase SHA-256 `planHash`, and both task/plan `planFile` values exactly
   `.contributor-docs/doc-plan.yaml`. Require task phase `write`, the live plan to
   exist, its fresh complete-byte SHA-256 to equal `planHash`, and the transient gap
   candidate to be absent. A missing or mismatched plan is
   `PLAN_DRIFT_BLOCKED: expected=<planHash> actual=<hash-or-absent>` and creates
   nothing.
5. Refuse if `.contributor-docs/write-state.json` already exists: report
   `ALREADY_INITIALIZED` and switch to Mode 1.
6. Write `.contributor-docs/write-state.json` with the initial phase schema — all
   fourteen canonical fields, mirroring
   `docs/standards/contributor-docs/write/PHASE.md`:

   <!-- canonical-block: write-state-schema -->

   ```json
   {
     "step": "scaffold",
     "authorizedPlanHash": "<plan-state.planHash>",
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

   `authorizedPlanHash` is copied from the freshly verified approved `planHash`; it is
   never accepted from the caller.

The legal write-step allowlist is this marked ten-element JSON array. Validation uses
this block rather than a free-form prose list.

<!-- canonical-block: write-legal-steps -->

```json
[
  "scaffold",
  "scaffold_blocked",
  "scaffold_prepared",
  "write_tier_1",
  "write_tier_2",
  "write_tier_3",
  "write_tier_4",
  "write_tier_5",
  "write_tier_6",
  "completed"
]
```

7. Validate every field before reporting success, not just parseability:
   - the file parses as JSON;
   - `step` is one of the values in `canonical-block: write-legal-steps`;
   - `authorizedPlanHash` is a lowercase SHA-256 equal to the approved plan hash;
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
3. Read and completely validate the immutable completed approved
   `.contributor-docs/plan-state.json`, including its exact task/plan path binding.
4. Validate the diff summary's source snapshot with the canonical workflow procedure,
   including its fresh equality to `plan-state.json.diffSummaryHash`. Derive
   `sourceSnapshotCurrent` and exact binding/drift evidence. A false result blocks
   every dispatch, including recovery, without changing state.
5. Read the exact live plan bytes only to hash them and check candidate presence/hash.
   When write state exists, validate the complete authority chain from
   `plan-state.planHash` through every ordered `gapsResolved[*].planMutation` and any
   live transition. Derive the six plan fields below. The only mismatch eligible for
   mutation is the fully valid `enqueued` `apply-gap-plan` tuple; every other mismatch
   in the live hash or lineage is `PLAN_DRIFT_BLOCKED` with byte-identical state and
   artifacts. A missing or wrong enqueued candidate while the authorized live hash is
   still current does not redefine plan drift: report `gapPlanApplyRequired: false` so
   Mode 3 can return `GAP_PLAN_CANDIDATE_MISSING` or `GAP_PLAN_HASH_INVALID`. When
   write state is absent, report that fact instead of inventing `authorizedPlanHash`;
   Mode 0 performs the prospective approved-root/live-plan check before creating it.
6. Check which `.contributor-docs/write-tier-N/state.json` files exist.
7. For existing tier states, check `pendingFiles` count.
8. Report current state.

**Counts come from `writeQueue` and `provenance`, never from `doc-plan.yaml`.** The
plan lists what was wanted; the queue records what was approved. Re-deriving per-tier
counts from the plan reintroduces every path the collision step refused, which is the
re-derivation `docs/standards/contributor-docs/write/PHASE.md` forbids. This mode reads
the exact plan bytes to hash them for identity, but does not parse the plan to derive a
count, queue member, tier slice, or provenance record.

### Report Format

```
CURRENT_STEP: <step from write-state.json>
CONTEXT:
- scaffoldComplete: <true|false>
- sourceSnapshotCurrent: <true|false>
- sourceSnapshotMismatch: <none | summary binding, identity/digest mismatch, or sorted outside dirty paths>
- approvedPlanHash: <plan-state.planHash>
- authorizedPlanHash: <write-state.authorizedPlanHash | absent before creation>
- livePlanHash: <64 lowercase hex | absent>
- planHashCurrent: <true|false>
- planHashMismatch: <none | exact expected/actual/lineage reason>
- gapPlanApplyRequired: <true|false>
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
- tierGapReports: <written current-tier writer reports whose gaps array is non-empty>
- tierPending: <pending files in current tier's processor state, if applicable>
```

When `gapPlanApplyRequired` is true, the exact `enqueued` apply/recovery tuple outranks
ordinary plan drift. Otherwise `planHashCurrent: false` outranks `gapTransition`; a
non-null transition with current plan identity outranks the ordinary step and must
finish before any tier dispatch.

When processor state says a path is pending but canonical provenance says `written`,
assessment reports it under `PROCESSOR_RECONCILE` only after a fresh disk hash equals
`writtenHash`. A mismatch is `WRITTEN_BYTES_CHANGED` and blocks dispatch.

## Mode 2: Commanded Write-State Operations

When prompted: `Update write state: {OPERATION_JSON}`

`OPERATION_JSON` must name exactly one operation below. A generic field patch is
refused with `UPDATE_REFUSED: operation required`; callers cannot manufacture a step
or counter by supplying its desired value.

### Universal Procedure

1. Read and completely validate write, task, and immutable approved plan state. For
   either audit-repair operation, also validate audit state and every cited current
   artifact.
2. Validate the canonical source snapshot. On any mismatch report
   `SOURCE_DRIFT_BLOCKED` and leave state and processor artifacts byte-identical.
3. Validate the full plan-authority chain and freshly require the live plan hash to
   equal `authorizedPlanHash`, with the candidate absent. On any mismatch report
   `PLAN_DRIFT_BLOCKED: expected=<hash> actual=<hash-or-absent>` and leave state,
   processor artifacts, task phase, and audit artifacts byte-identical. This guard
   precedes every ordinary, repair, collision, processor, writer, completion, and
   handoff operation.
4. Refuse Mode 2 while `gapTransition != null`; Mode 3 exclusively owns that graph.
5. Validate every path as normalized, root-relative, and contained by `docsRoot`.
6. For an agent report that consumed plan metadata, require its lowercase 64-hex
   `PLAN_SHA256` to equal `authorizedPlanHash`, and freshly rehash the live plan at
   acceptance time.
7. Build the operation's complete candidate object, derive both counters, and enforce
   the source step, target step, and target invariants below.
8. Validate before writing, then use a temp file plus atomic rename.
9. When the step changes, append the transition only after the rename.

### Legal Operations

| Operation                      | Legal source        | Required validation and atomic effect                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ------------------------------ | ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `prepare-scaffold`             | `scaffold`          | Validate a whole-plan, exact-byte manifest, its hashes, and reported `PLAN_SHA256`. Persist writable queue/provenance with `scaffoldedAt: null`, measure every collision, derive totals, then move to `scaffold_blocked` or `scaffold_prepared`. No target file may have been written.                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `resolve-scaffold`             | `scaffold_blocked`  | Require approve/skip for the exact blocked set. Freshly match every approval to `observedHash`; append hash-bound scaffold approvals, update queue/provenance, clear only resolved collisions, derive totals, and reach `scaffold_prepared` only when none remain.                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `block-scaffold`               | `scaffold_prepared` | Freshly measure a create-time collision, record its exact current/expected hashes, and move to `scaffold_blocked`. Prepared hashes and already-created matching files remain adoptable.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `finalize-scaffold`            | `scaffold_prepared` | Require zero collisions, current reported `PLAN_SHA256`, and freshly hash every queued file to its prepared `scaffoldHash`; fill null `scaffoldedAt`, consume used scaffold approvals, set `scaffoldComplete: true`, derive counters, and move to `write_tier_1`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `reopen-audit-repair`          | `completed`         | Require task/audit failure with nonzero current stamped errors, an existing marker that is null or older than the current audit epoch, and a non-empty exact set of queued paths named by those errors. Validate the completed resting state without requiring live hashes, then measure mismatches as collisions. Remove and verify absent every processor state/findings tree from the lowest selected tier through 6. Atomically install the current epoch-bound `auditRepair: replaying` marker, restore only those paths to pending while retaining `writtenHash` and clearing `writerReport`, truncate tier completion, derive counters, and enter the lowest selected tier. After that rename, move task phase `failed → write`. |
| `resume-audit-repair-phase`    | `write_tier_N`      | Crash reconciliation for the prior operation: require task phase still `failed`, audit step `failed`, and at least one pending path that retains a `writtenHash` and is named by current stamped errors. A collided path still satisfies this retained-provenance test. Require the matching `auditRepair: replaying` marker, then update only task phase to `write`.                                                                                                                                                                                                                                                                                                                                                                   |
| `record-writer-collision`      | `write_tier_N`      | Freshly hash one pending path that differs from its retained normal authority, atomically replace that path's collision record with exact observed/expected hashes, and keep the tier step. Any nonempty collision set blocks dispatch.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `approve-writer-replay`        | `write_tier_N`      | Require an existing collision and an explicit user decision, freshly match `observedHash`, append an unconsumed `purpose: "writer-replay"` approval, and remove that collision atomically. A changed path is remeasured and remains blocked.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `authorize-processor-init`     | `write_tier_N`      | Read-only. After the universal fresh fence, require no collision and derive the exact current-tier pending slice from queue/provenance. Return that slice and `authorizedPlanHash` for `init-state.sh`; accept neither from the caller. An empty slice is still an authorized result.                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `authorize-processor-complete` | `write_tier_N`      | Read-only. After the universal fresh fence, require the exact path in the current tier, written status, a complete bound `writerReport`, and a fresh disk hash equal to `writtenHash`. Return `authorizedPlanHash` for the immediately following `mark-done.sh`; mutate nothing.                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `record-write`                 | `write_tier_N`      | Require the path in the current tier, pending status, a report carrying current `PLAN_SHA256`, valid `AUTHORIZED_FROM_HASH` and `WRITTEN_HASH`, a complete structured `GAPS` field, and a legal start authorization. Freshly rehash plan and disk; validate and normalize every gap; then atomically record written status/hash plus the complete bound `writerReport`, derive `filesWritten`, and consume the exact replay approval if one authorized it.                                                                                                                                                                                                                                                                              |
| `complete-tier`                | `write_tier_N`      | Require current plan identity, zero collisions, the processor empty, every tier path written with a non-null complete `writerReport`, and every fresh disk hash equal to `writtenHash`. Append N once. Advance to tier N+1, or keep `currentTier: 6` and reach `completed` after tier 6.                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `advance-task-phase-to-audit`  | `completed`         | Require current full plan authority, complete-step invariants, and fresh live hashes. On the initial write, atomically update task phase `write → audit`. During repair, require the matching `auditRepair: replaying` marker and failed audit, freshly verify every marked path, atomically set the marker to `completed`, then update task phase `write → audit`. A retry that sees the completed marker with task phase still `write` finishes only the second rename.                                                                                                                                                                                                                                                               |

`record-write` accepts a start authorization only when
`AUTHORIZED_FROM_HASH` equals the first-write `scaffoldHash`, the retained replay
`writtenHash`, or the `approvedHash` of one unconsumed writer-replay approval for the
same path. An approval does not mutate `writtenHash` and cannot be selected twice.
The writer performs the same fresh pre-write check; the state-agent independently
checks the returned bytes before completion.

The writer report is part of that same commit, not a later collection step. Normalize
`GAPS: none` to `gaps: []`. Otherwise require every item to have exactly path, type,
tier, and a non-blank reason; enforce concept→2 and algorithm→3; reject duplicate or
conflicting metadata for one path; and require every path normalized and contained by
`docsRoot`. Store exactly the marked five-field `writerReport` with `reportedBy` equal
to the provenance key, `authorizedPlanHash` equal to the freshly verified authority,
`authorizedFromHash` equal to the selected start authorization, and `writtenHash` equal
to the fresh disk hash. `GAP_REPORT_SET_INVALID` leaves canonical and processor state
byte-identical, so a malformed report cannot be silently dropped while its file is
declared complete.

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

- Every step has a lowercase SHA-256 `authorizedPlanHash` whose complete lineage starts
  at immutable `plan-state.planHash`. With `gapTransition: null`, it equals a fresh
  live-plan hash and the gap candidate is absent.
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

- The object has exactly the canonical fourteen keys and a `step` contained in the
  marked ten-value `canonical-block: write-legal-steps` array.
- `authorizedPlanHash` is a lowercase SHA-256. It begins equal to immutable
  `plan-state.planHash`; only `apply-gap-plan` may advance it to the exact next
  `planMutation.toPlanHash`.
- `scaffoldComplete` is boolean; `currentTier` is an integer 0–6;
  `tiersCompleted` is a sorted, duplicate-free integer array.
- Both counters are non-negative integers; `filesTotal == writeQueue.length` and
  `filesWritten` equals the number of written provenance entries.
- `writeQueue` contains unique, normalized strings under `docsRoot`; its set equals
  the provenance key set.
- Every provenance value has exactly the seven fields below. `scaffoldHash` and every
  non-null `writtenHash` are lowercase SHA-256 values; `scaffoldedAt` is null only in
  a scaffold preparation step. Pending status requires `writerReport: null`; written
  status requires a non-null `writtenHash` and the exact five-field writer report whose
  reporter and three hashes equal the provenance path, current authority, accepted
  start hash, and `writtenHash`. Each gap has exactly the canonical four fields, a
  non-blank reason, and a legal type/tier pair.
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
  records with the complete ten transition fields plus `closedAt`, status exactly
  `cleared`, unique `openedAt`, valid complete reports/reasons, exact derived gap tuples,
  complete cleanup evidence, and the five-field `planMutation`. Walking them in append
  order from `plan-state.planHash` must end at
  `authorizedPlanHash == SHA256(live plan)`, and the candidate sidecar must be absent.
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
    "writtenHash": null,
    "writerReport": null
  }
}
```

<!-- canonical-block: write-writer-report-record -->

```json
{
  "reportedBy": "docs/contributor/orders/features/checkout.mdx",
  "authorizedPlanHash": "<the accepted PLAN_SHA256>",
  "authorizedFromHash": "<the accepted AUTHORIZED_FROM_HASH>",
  "writtenHash": "<the accepted WRITTEN_HASH>",
  "gaps": [
    {
      "path": "docs/contributor/orders/concepts/idempotency.mdx",
      "type": "concept",
      "tier": 2,
      "reason": "Checkout needs the shared idempotency contract"
    }
  ]
}
```

`writerReport` is null exactly while a path is pending. A successful `record-write`
installs the complete record above in the same atomic rename as written status/hash;
`GAPS: none` is represented by `gaps: []`. Requeue operations clear the record while
retaining `writtenHash`, because the live or closed transition already owns any report
it consumed and the replay must produce a fresh report.

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
The legal operation names are `authorize-gap-plan`, `apply-gap-plan`, `prepare`,
`approve-collision`, `scaffold`, `apply`, `clean`, and `clear`.
Before any edge or collision decision, validate the canonical source snapshot. A
mismatch is `SOURCE_DRIFT_BLOCKED` and leaves the entire transition byte-identical.
Next validate the complete plan-authority chain. `authorize-gap-plan` and every edge
after `planned` require ordinary current plan identity. `apply-gap-plan` alone accepts
the exact `enqueued` candidate/live tuples described below; no other mismatch may
mutate anything.

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
          "type": "concept",
          "tier": 2,
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
  "openedAt": "<ISO-8601>",
  "planMutation": {
    "candidatePath": ".contributor-docs/doc-plan.gap-candidate.yaml",
    "fromPlanHash": "<64 lowercase hex>",
    "toPlanHash": "<64 lowercase hex>",
    "addedPlanEntries": [
      {
        "outputPath": "docs/contributor/orders/concepts/idempotency.mdx",
        "container": "module:orders",
        "entry": {
          "path": "orders/concepts/idempotency.mdx",
          "type": "concept",
          "tier": 2,
          "description": "Checkout needs the shared idempotency contract",
          "sources": ["src/orders/checkout.ts"]
        }
      }
    ],
    "addedCrossLinks": [
      {
        "reportedBy": "docs/contributor/orders/features/checkout.mdx",
        "field": "concepts",
        "target": "docs/contributor/orders/concepts/idempotency.mdx"
      }
    ]
  }
}
```

<!-- canonical-block: gap-plan-mutation-record -->

```json
{
  "candidatePath": ".contributor-docs/doc-plan.gap-candidate.yaml",
  "fromPlanHash": "<64 lowercase hex>",
  "toPlanHash": "<64 lowercase hex>",
  "addedPlanEntries": [
    {
      "outputPath": "docs/contributor/orders/concepts/idempotency.mdx",
      "container": "module:orders",
      "entry": {
        "path": "orders/concepts/idempotency.mdx",
        "type": "concept",
        "tier": 2,
        "description": "Checkout needs the shared idempotency contract",
        "sources": ["src/orders/checkout.ts"]
      }
    }
  ],
  "addedCrossLinks": [
    {
      "reportedBy": "docs/contributor/orders/features/checkout.mdx",
      "field": "concepts",
      "target": "docs/contributor/orders/concepts/idempotency.mdx"
    }
  ]
}
```

### Sub-operation `authorize-gap-plan`

Call only at the tier boundary, after every path is canonically written. The
orchestrator must already have prepared the fixed
`.contributor-docs/doc-plan.gap-candidate.yaml` sidecar from the state-agent's assessed
ledger view, but it must not change the live plan. Require `gapTransition: null`,
ordinary current plan identity except for this operation's narrow candidate-presence
input window, and no prior candidate authority. This is the sole operation allowed to
inspect a candidate while no live gap exists.

Independently derive `reports` from current-tier provenance entries whose complete
`writerReport.gaps` is non-empty, sorted by provenance path. Never accept reports or
gap paths from the caller. Require the set non-empty; every reporter must be a
normalized queued path in the current tier with written status, matching current
authority/written hashes, and every nested gap must retain the exact normalized `path`,
`type`, `tier`, and non-empty `reason` that `record-write` committed. Independently
derive `gapPaths` by de-duplicating the reported `(path, type, tier)` tuples. Refuse
conflicting type/tier reports for one path or any malformed ledger item. Validate
containment under `docsRoot`, concept/algorithm type-to-tier rules, no current queue
member, the loop guard, and independently
recompute `requeued`, `replayTier`, and `resetTiers` from `writeQueue` plus current
authorized plan metadata. `replayTier` may not exceed `currentTier`.

Parse and completely validate both current and candidate plans. Independently derive
the exact semantic delta; never accept `planMutation` from the caller. Candidate-only
paths must equal `gapPaths`; every complete new entry must match its gap path/type/tier;
the only additions to existing entries are the exact reporter-to-gap `concepts` or
`algorithms` edges; and no existing scalar, source, tag, description, module metadata,
entry, key, or unrelated link may change or disappear. Capture complete added mappings
with stable container selectors and sort entries by `outputPath` and links by
`(reportedBy, field, target)` under `LC_ALL=C`. A semantic mismatch is
`GAP_PLAN_DELTA_INVALID` with no mutation.

Freshly require the live-plan hash to equal `authorizedPlanHash`; store it as
`fromPlanHash`. Freshly hash the complete candidate bytes as `toPlanHash` and require
the hashes to differ. Candidate absence is `GAP_PLAN_CANDIDATE_MISSING`. One atomic
state write installs `status: "enqueued"`, the exact reports, derived `gapPaths`, other computed values, empty
`expectedScaffold`/`cleanedTiers`, `openedAt`, and the complete five-field
`planMutation`. It does not change the live plan, candidate, queue, or
`authorizedPlanHash`.

### Sub-operation `apply-gap-plan`

The ordinary legal source is `enqueued`. First validate the immutable approved root,
the ordered closed-gap chain, and the live transition's stored five-field mutation.
Require `candidatePath` to be the fixed sidecar and
`authorizedPlanHash == fromPlanHash == derived cursor`.

- Normal tuple: live plan freshly hashes to `fromPlanHash`, and the candidate exists
  and freshly hashes to `toPlanHash`. Atomically rename that exact candidate over
  `.contributor-docs/doc-plan.yaml`, freshly rehash the installed bytes, then
  atomically set `authorizedPlanHash = toPlanHash` and status `planned` in the same
  write-state rename.
- Crash tuple: live plan already hashes to `toPlanHash`, the candidate is absent, and
  state is still enqueued/from. The candidate rename committed before the state
  rename; perform only that same authorized-hash/status state update.
- Idempotent tuple: status is already `planned`, `authorizedPlanHash == toPlanHash`,
  the live hash equals it, and the candidate is absent. Report success without a
  write.

Candidate absence in the normal tuple is `GAP_PLAN_CANDIDATE_MISSING`. Candidate or
live bytes that do not match the required stored endpoint are
`GAP_PLAN_HASH_INVALID`. Every refusal leaves both plans, all state, processor files,
task phase, and audit artifacts byte-identical. No other operation may update
`authorizedPlanHash`.

### Sub-operation `prepare`

Legal only from `planned`. Accept the scaffolder's machine-readable exact-byte
manifest and reported `PLAN_SHA256`, freshly require the full chain/live hash current
and candidate absent, recompute every scaffold hash, and require its path set to equal
`gapPaths` exactly. `expectedScaffold` therefore has neither missing nor extra keys and
every value is a lowercase SHA-256.

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
current plan identity and an explicit per-path user approval, freshly match the current
bytes to `observedHash`, and atomically append an unconsumed `purpose: "scaffold"`
approval while removing only that collision. A changed hash is remeasured and remains
blocked. `skip` is refused because every gap path is a required dependency; abandoning
it requires failing the workflow rather than clearing recovery state.

### Sub-operation `scaffold`

Legal only from `prepared`. Freshly require current plan identity and the scaffolder's
reported `PLAN_SHA256`. The scaffolder re-renders exact bytes and must match every
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
`GAP_TRANSITION_INVALID`. Freshly require current plan identity and candidate absence.
It performs, together:

1. `tiersCompleted` truncated to the tiers strictly less than `replayTier`
2. `currentTier: replayTier` and `step: "write_tier_<replayTier>"`
3. every path in `requeued` set to `writeStatus: "pending"`, **keeping** its
   `writtenHash` and clearing `writerReport` — the retained hash is the authorization
   the replaying writer checks, while the live transition now owns the durable report
4. `filesWritten` recomputed from provenance
5. `status: "reset"`

The state rename commits every effect together. A retry that observes `status: "reset"`
reports `GAP: applied` without rewriting; a retry that still observes `scaffolded`
applies the edge once.

### Sub-operation `clean`

Legal only from `reset`. Freshly require current plan identity and candidate absence.
Select the first `resetTiers` member absent from `cleanedTiers`. Remove its exact
processor `state.json` and findings tree, then verify both are absent. Only after that
verification does one atomic state write append the tier. When the sorted, unique
`cleanedTiers` set equals `resetTiers`, the same write sets `status: "cleaned"`. A
failed removal reports `GAP_CLEANUP_INCOMPLETE` and changes no state. Missing artifacts
are already absent, so retries are idempotent.

### Sub-operation `clear`

One atomic write, legal only when `status == "cleaned"`; otherwise report
`GAP_CLEANUP_INCOMPLETE`. **Refuse to clear while `cleanedTiers` does not cover
`resetTiers`.** Freshly require current plan identity, candidate absence, and the live
transition's `toPlanHash == authorizedPlanHash`. Clearing early would leave a completed-looking processor state on disk
for a tier that now has pending work, and the tier initializer would skip the replayed
files while every counter reported success.

`clear` appends the complete ten-field copy, including every report/reason, exact gap
tuple, replay/cleanup field, timestamps, and unchanged `planMutation`, with status
`cleared` plus `closedAt` to `gapsResolved` and sets `gapTransition: null` in one atomic
rename. Validate the complete eleven-field result before writing. The append is
idempotent by `openedAt`: if `gapsResolved` already holds the exact closed entry with
this `openedAt`, do not append a second one; a missing, duplicate, or conflicting
history is `GAP_CLOSURE_INVALID`, not an invitation to repair history.

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

- The live record has exactly the ten marked fields. `reports` is non-empty, each
  nested gap retains the writer's exact path, type, tier, and non-empty reason, and
  `gapPaths` is the de-duplicated exact `(path, type, tier)` tuple set derived from
  those reports. Conflicting metadata for one path is invalid; every reporter and gap
  path passes containment and membership checks.
- `planMutation` has exactly the five marked fields. Its candidate path is fixed, both
  endpoints are distinct lowercase SHA-256 values, `addedPlanEntries` captures every
  complete new YAML mapping with a stable container selector and, under `LC_ALL=C`, is
  sorted by `outputPath`; `addedCrossLinks` is sorted by
  `(reportedBy, field, target)` and equals the exact reporter edges.
- `expectedScaffold` is empty at enqueued/planned and has exact gap-path key coverage
  at prepared and later statuses.
- At `enqueued`, `authorizedPlanHash == fromPlanHash ==` the closed-chain cursor. The
  normal tuple has live/from plus candidate/to; the sole crash tuple has live/to and
  no candidate. At planned and later statuses, live/authorized/to are equal and the
  candidate is absent.
- `cleanedTiers` is always a duplicate-free subset of `resetTiers`; cleaned requires
  exact equality and verified artifact absence.
- `gapsResolved` records have the ten core fields plus `closedAt`, status exactly
  `cleared`, non-blank complete reports, exact derived gap tuples, complete cleanup
  evidence, and unique `openedAt`. They form one append-ordered, gap-free chain from
  immutable `plan-state.planHash` to the live transition/current authorized hash.
- `PLAN_DRIFT_BLOCKED`, `GAP_PLAN_DELTA_INVALID`, `GAP_PLAN_HASH_INVALID`,
  `GAP_PLAN_CANDIDATE_MISSING`, `GAP_IN_FLIGHT`, `GAP_REPORTER_INVALID`,
  `GAP_REPORT_SET_INVALID`, `GAP_CLOSURE_INVALID`, `GAP_PATH_INVALID`,
  `GAP_ALREADY_QUEUED`, `GAP_LOOP`,
  `GAP_TIER_INVALID`, `GAP_MANIFEST_INVALID`, `GAP_COLLISION`,
  `GAP_TRANSITION_INVALID`, `GAP_CLEANUP_INCOMPLETE`, and `WRITE_REPORT_MISSING` leave
  the prior state, plans, processors, task phase, and audit artifacts byte-identical.
  The sole narrow exception is a collision-measurement operation, which may atomically
  replace `blockedCollisions` while retaining the same transition status.

## Important

- Manage `write-state.json` and `task-state.json` (phase transitions only)
- Do not plan or write documentation content.
- The orchestrator may prepare the fixed gap candidate, but it never edits the live
  plan. Mode 3 independently authorizes and installs only those exact candidate bytes;
  the scaffolder authors scaffold bytes and Mode 3 owns reset-processor deletion.
- Mode 2 owns write-tier processor cleanup for `reopen-audit-repair`; documentation
  fixes themselves still run through doc-writers and `record-write`.
- Never accept a caller-supplied status without executing its named edge operation.
- Never update `authorizedPlanHash` outside the successful/idempotent
  `apply-gap-plan` edge.
