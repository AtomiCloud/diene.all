# Phase 2: Write

## State Machine

```
[scaffold] → [scaffold_prepared] → [write_tier_1] → [write_tier_2] → [write_tier_3]
     │                  ↑             fp-loop(S)×N      fp-loop(S)×N      fp-loop(S)×N
     └→ [scaffold_blocked] ───────────┘

[write_tier_3] → [write_tier_4] → [write_tier_5] → [write_tier_6] → [completed]
   fp-loop(S)×N      fp-loop(S)×N      fp-loop(S)×N      fp-loop(S)×N

any [write_tier_N] --(gap reports)--> gapTransition --(replay)--> [write_tier_<replayTier>]
```

Scaffold is a single team agent. Each write tier uses the file-processor loop with parallel sonnet agents.

The march through the tiers is linear except for one edge: writers that discover a
missing dependency open one durable `gapTransition` and replay an earlier tier. That
edge is not an error path — it is the [Discovered-Gap
Transition](#discovered-gap-transition), and this file owns its mechanism.

## State File: `write-state.json`

<!-- canonical-block: write-state-schema -->

```json
{
  "step": "scaffold | scaffold_blocked | scaffold_prepared | write_tier_1 | write_tier_2 | write_tier_3 | write_tier_4 | write_tier_5 | write_tier_6 | completed",
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

This is the **canonical write-phase schema** — thirteen top-level fields, and this file
is their single source of truth. The write state-agent's create, assess, update and
gap modes operate on exactly these fields: no more, no fewer, and an unknown field is
refused rather than merged. The state-agent mirrors this block verbatim; where the two
ever disagree, this file takes precedence and the mirror is repaired here first.

The HTML comment above the block is a marker, not decoration. Both this file and
`docs/standards/contributor-docs/write/state-agent.md` carry the same marker above
their copy of the schema, so a field-set comparison can select exactly the canonical
block instead of guessing which fenced `json` block it wanted. See
[Consistency Checks](#consistency-checks).

### The Durable Write Queue

| Field                | Type           | Meaning                                                                |
| -------------------- | -------------- | ---------------------------------------------------------------------- |
| `writeQueue`         | array of paths | The **only** paths any tier may process. Nothing else is ever written. |
| `provenance`         | path → record  | How each queued path was classified, and the evidence for it           |
| `approvedOverwrites` | array          | Append-only, exact-hash approvals and whether each was consumed        |
| `blockedCollisions`  | array          | Current exact-hash collisions awaiting a per-path decision             |
| `auditRepair`        | object or null | Epoch-bound proof of an authorized audit-repair replay                 |
| `gapTransition`      | object or null | The in-flight discovered-gap transition; non-null blocks tier dispatch |
| `gapsResolved`       | array          | Append-only log of closed transitions, one entry per completed replay  |

Each `provenance` entry is:

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

Preparation records `scaffoldHash` before any bytes are created and leaves
`scaffoldedAt: null`. Finalization freshly hashes the file and fills `scaffoldedAt`
only after the current bytes match that prepared hash. No tier may run while any
queued provenance entry still has a null `scaffoldedAt`.

Each `approvedOverwrites` entry is an append-only, one-use authority:

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

An approval authorizes only the current bytes matching `approvedHash`, only for its
named `purpose`, and only while `consumedAt` is null. A path may therefore appear more
than once when the user approves different snapshots at different times. Consuming an
approval fills `consumedAt`; entries are never deleted or silently reused.
At most one unconsumed approval may exist for a path and purpose, and appending one
requires the path's current collision record.

`auditRepair` is null on the initial write. Audit repair installs this exact record
before reopening any path:

<!-- canonical-block: write-audit-repair-record -->

```json
{
  "auditEpoch": 1,
  "docsDigest": "39e77a6619ba41e414906e08eb0f1d62d3069469c2b7cd5f702058869f256fb9",
  "paths": ["docs/contributor/orders/features/checkout.mdx"],
  "status": "replaying | completed"
}
```

The record is the positive evidence that distinguishes a completed repair from an
audit-failure task-phase crash. `reopen-audit-repair` requires the existing marker to
be null or bound to an older audit epoch, then creates `replaying` with the current
failed audit's exact epoch, digest, and selected queued paths. A marker already bound
to the current epoch is never replaced.
`advance-task-phase-to-audit` changes it to `completed` only after those paths have
passed the ordinary writer and live-hash checks. A record from an older audit epoch is
inert history: it cannot authorize reset and may be replaced only when a later failed
epoch starts another repair.

Each `blockedCollisions` entry binds the refusal to both sides of the proposed write:

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

Approval is accepted only if a fresh hash still equals `observedHash`. If it changed,
the stale decision is refused and a new collision record is measured. Skipping a
collision removes it from this run; approving it appends an exact-hash approval and
adds or updates its prepared queue/provenance entry atomically.

`writeStatus` and `writtenHash` are the per-path provenance state. Together they
distinguish the three situations a replay has to tell apart, which no single flag can:

| `writeStatus` | `writtenHash` | Situation                   | What a writer may do                                  |
| ------------- | ------------- | --------------------------- | ----------------------------------------------------- |
| `pending`     | `null`        | Scaffolded, never written   | Write, if current bytes hash to `scaffoldHash`        |
| `written`     | `<sha256>`    | Body complete               | Nothing — the path is not tier input at all           |
| `pending`     | `<sha256>`    | Authorized replay of a body | Rewrite, if current bytes still hash to `writtenHash` |

**`writtenHash` is recorded whenever a writer completes**, in the same state update
that sets `writeStatus: "written"`. The writer must report it, and the state-agent
freshly hashes the disk and requires equality before installing either field. On a
replay the transition sets `writeStatus` back to `pending` and
**keeps** `writtenHash`, and that retained hash — not the pending status — is the
overwrite authority. `writeStatus: "pending"` on its own authorizes nothing: a path
whose bytes match neither `scaffoldHash` nor `writtenHash` changed under the workflow
(a half-written body from a crashed writer, or an outside edit) and is refused, exactly
as an unclassified collision is refused.

**Ownership is proven by a pre-write durable hash, never inferred from shape.** A
finalized file is a run-owned scaffold only if its current bytes hash to provenance
`scaffoldHash`; during gap create, the temporary authority is
`gapTransition.expectedScaffold[path]`. A pre-existing draft that happens to be one
line long is _not_ a scaffold, and no heuristic about "looks like a summary" may be
used to decide it is. If no status-appropriate hash matches, the path needs explicit
approval.

## Step Dispatch

| Step                | Agent         | Model  | Type    | File                                                  | Description                                |
| ------------------- | ------------- | ------ | ------- | ----------------------------------------------------- | ------------------------------------------ |
| `scaffold`          | scaffolder    | sonnet | team    | `docs/standards/contributor-docs/write/scaffold.md`   | Prepare the whole-plan manifest            |
| `scaffold_blocked`  | none          | —      | hold    | —                                                     | Await exact per-path collision decisions   |
| `scaffold_prepared` | scaffolder    | sonnet | team    | `docs/standards/contributor-docs/write/scaffold.md`   | Create/adopt the prepared initial scaffold |
| `write_tier_1`      | doc-writer ×N | sonnet | fp-loop | `docs/standards/contributor-docs/write/write-file.md` | Tier 1: foundations                        |
| `write_tier_2`      | doc-writer ×N | sonnet | fp-loop | `docs/standards/contributor-docs/write/write-file.md` | Tier 2: concepts                           |
| `write_tier_3`      | doc-writer ×N | sonnet | fp-loop | `docs/standards/contributor-docs/write/write-file.md` | Tier 3: algorithms                         |
| `write_tier_4`      | doc-writer ×N | sonnet | fp-loop | `docs/standards/contributor-docs/write/write-file.md` | Tier 4: features                           |
| `write_tier_5`      | doc-writer ×N | sonnet | fp-loop | `docs/standards/contributor-docs/write/write-file.md` | Tier 5: surfaces                           |
| `write_tier_6`      | doc-writer ×N | sonnet | fp-loop | `docs/standards/contributor-docs/write/write-file.md` | Tier 6: indexes                            |
| `completed`         | none          | —      | handoff | —                                                     | Advance task phase to audit                |

### Gap Sub-Dispatch

Gap statuses are not write steps and therefore have their own table.

| Gap status | Agent      | Model  | Type | File                                                | Description                            |
| ---------- | ---------- | ------ | ---- | --------------------------------------------------- | -------------------------------------- |
| `planned`  | scaffolder | sonnet | team | `docs/standards/contributor-docs/write/scaffold.md` | Prepare `gapTransition.gapPaths`       |
| `prepared` | scaffolder | sonnet | team | `docs/standards/contributor-docs/write/scaffold.md` | Create/adopt the prepared gap scaffold |

All write tiers use the same agent file (`write-file.md`), parameterized with the tier
number and file metadata. Every scaffold dispatch uses the same agent file
(`scaffold.md`), parameterized with an explicit `prepare` or `create` operation and
**the exact path set it may inspect** — the whole plan on first entry or
`gapTransition.gapPaths` during recovery. The scaffolder never chooses its own input
set and a `prepare` operation never writes.

## Step Dispatch Logic

On entry, spawn write state-agent to assess. **NEVER read step files directly** — spawn a teammate and tell it which step file to read. The file-processor loop is managed by the orchestrator using scripts.

Conditions are evaluated **in order**. The first row wins.

| #   | Condition                      | Action                                                                                                                                                                      |
| --- | ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `sourceSnapshotCurrent: false` | Report `SOURCE_DRIFT_BLOCKED` with exact drift evidence and mutate nothing                                                                                                  |
| 2   | `gapTransition != null`        | **Finish the in-flight transition first** — resume its exact operation from `status`. No initial scaffold or tier may run.                                                  |
| 3   | No `write-state.json`          | Create via state-agent with `step: "scaffold"`, then reassess                                                                                                               |
| 4   | `blockedCollisions` nonempty   | Present every measured collision; invoke `resolve-scaffold` at `scaffold_blocked` or `approve-writer-replay` in a write tier; dispatch no writer until the exact set clears |
| 5   | `step: "scaffold"`             | Spawn scaffolder `prepare`, input set = the whole plan; invoke `prepare-scaffold` on its complete manifest                                                                  |
| 6   | `step: "scaffold_blocked"`     | Invalid without collisions — state-agent reports the broken invariant                                                                                                       |
| 7   | `step: "scaffold_prepared"`    | Spawn scaffolder `create`, input set = prepared `writeQueue`; invoke `block-scaffold` for any mismatch, otherwise `finalize-scaffold`                                       |
| 8   | `step: "write_tier_N"`         | Reconcile canonical written records with processor state, then run the file-processor loop for tier N                                                                       |
| 9   | `step: "completed"`            | Invoke state-agent `advance-task-phase-to-audit`; do not issue a generic phase update                                                                                       |

Source drift takes precedence over every write or recovery action. Once it is clear,
the gap row takes precedence over the step because a transition that is half-applied has a
`step` that is not yet true. Dispatching on it would run a tier against a queue the
transition has not finished extending.

## Initial Scaffold Protocol

Initial scaffolding is a durable prepare → create → finalize protocol. A one-shot
"create, then report" is forbidden: a crash after the filesystem write but before the
state write would leave an ownerless file that the retry correctly treats as a
collision.

### 1. Prepare — `prepare-scaffold`

The scaffolder classifies the **entire** whole-plan input, renders the exact bytes for
each proposed scaffold in memory, and returns a machine-readable manifest containing
path, tier, disposition, exact bytes, SHA-256, and (for a collision) the current hash
and line count. It writes nothing.

The state-agent validates exact input coverage, normalized root-relative paths under
`docsRoot`, and every reported hash. The orchestrator invokes `prepare-scaffold`,
which in one atomic operation:

1. records the writable paths in `writeQueue` and creates their prepared `provenance`
   entries with `scaffoldedAt: null`;
2. records every collision as a hash-bound `blockedCollisions` entry;
3. sets `filesTotal` from the queue; and
4. moves `scaffold → scaffold_blocked` when collisions exist, otherwise
   `scaffold → scaffold_prepared`.

The exact bytes stay in the scaffolder report; state persists their expected hashes.
The later create operation must re-render the bytes and prove their hashes equal the
persisted values, so plan drift cannot change a prepared write.

### 2. Resolve Collisions — `resolve-scaffold`

`scaffold_blocked` dispatches no writer. The user decides every blocked path
individually. The orchestrator invokes `resolve-scaffold`; the state-agent requires a
decision for the exact current collision set:

- `skip` removes the path from this run;
- `approve` is accepted only while a fresh disk hash still equals `observedHash`,
  appends a one-use `purpose: "scaffold"` approval, and adds or updates the path's
  prepared queue/provenance record.

The decisions, queue, provenance, approval ledger, cleared collision set,
`filesTotal`, and `step: "scaffold_prepared"` land atomically. A changed path is
remeasured and remains blocked; approval never follows a stale hash.

### 3. Create and Finalize — `block-scaffold` / `finalize-scaffold`

The scaffolder's `create` operation re-renders each prepared path and first requires
the render hash to equal `provenance[path].scaffoldHash`. It then applies exactly one
of these rules:

| Prepared origin      | Current filesystem state that permits create/adopt                                                                                   |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `new`                | absent → create; expected scaffold hash → adopt a crash-completed write                                                              |
| `run-owned-scaffold` | expected scaffold hash → adopt                                                                                                       |
| `approved-overwrite` | exact hash of an unconsumed `purpose: "scaffold"` approval → create; expected scaffold hash → adopt a crash-completed approved write |

Anything else is a newly measured collision. The orchestrator invokes
`block-scaffold`; the state-agent atomically records it and returns the step to
`scaffold_blocked`; a partially created set is harmless
because every created path has a persisted expected hash and is adopted on retry.

After the scaffolder reports, the orchestrator invokes `finalize-scaffold`. The
state-agent freshly hashes **every** queued path. Only when each equals its prepared
`scaffoldHash` does that atomic operation
fill null `scaffoldedAt` values, consume any used scaffold approvals, clear collisions,
set `scaffoldComplete: true`, recompute both counters, and move
`scaffold_prepared → write_tier_1` with `currentTier: 1`. No tier is reachable before
that barrier.

## Audit-Repair Replay

Audit content errors never authorize direct edits. When current stamped audit
artifacts name documentation paths that need repair, the orchestrator invokes write
state-agent `reopen-audit-repair` with that exact non-empty path set.

The operation is legal only from write step `completed`, audit step `failed`, task
phase `failed`, derived `currentContentErrors > 0`, and an `auditRepair` marker that is
null or belongs to an older audit epoch. It never replaces a marker already bound to
the current epoch. It validates that every selected path:

- is a unique normalized member of `writeQueue` with written provenance;
- is named by at least one current-epoch, current-digest error artifact rather than a
  warning or caller assertion; and
- either still hashes to its retained `writtenHash` or is measured into an exact
  `blockedCollisions` record.

Let `repairTier` be the lowest selected provenance tier. Before changing canonical
state, the state-agent removes and verifies absent each
`.contributor-docs/write-tier-N/state.json` and findings tree for every tier from
`repairTier` through 6. Cleanup-first is crash safe: losing only a processor cache
does not change completed provenance, and retry repeats the absence checks.

One atomic write then installs `auditRepair` with the current audit epoch/digest,
the exact selected paths, and `status: "replaying"`; sets only those paths back to
`pending`; keeps every `writtenHash`; truncates `tiersCompleted` below `repairTier`; sets
`currentTier: repairTier` and `step: "write_tier_<repairTier>"`, persists any measured
collisions, and derives `filesWritten`. It does not change scaffold ownership or add a
queue member. After that commit marker, the state-agent changes task phase
`failed → write`; a crash between the two renames is reconciled by the named
`resume-audit-repair-phase` operation, never by a generic phase patch.

Ordinary tier dispatch then applies unchanged. A normal retained hash authorizes the
replay; a mismatch blocks until one fresh `purpose: "writer-replay"` approval is
consumed by a successful, freshly verified `record-write`. The orchestrator supplies
each repair writer both its current audit errors and the complete normalized
`plannedPaths` set from the current plan at dispatch time. A stamped
`missing-dependency` error whose proposed path is absent from that set must be returned
in the writer's `GAPS` report so the normal discovered-gap transition adds and replays
the dependency. If its proposed path has since joined `plannedPaths`, the writer
downgrades the retained error to an ordinary link-only repair and produces no gap item.

After all tiers reach `completed`, `advance-task-phase-to-audit` freshly validates the
marker's epoch/digest, every marked path's written status, and every live
`writtenHash`. It first changes the marker to `completed`, then moves task phase
`write → audit`. A crash between those renames is an idempotent retry: the completed
marker authorizes only finishing the task-phase rename. The marker — not task phase or
the still-failed audit counters alone — proves that a writer-authorized repair cycle
finished. Only then may audit reset to a fresh epoch. No direct document edit, stale
`writtenHash`, or completed processor cache can bypass this replay.

## File-Processor Loop (Per Tier)

For each `write_tier_N` step:

### 1. Initialize

Before computing new input, reconcile processor state with canonical provenance. A
crash may occur after the state-agent records a verified write but before
`mark-done.sh` updates the processor. For each processor-pending path already marked
`written` in provenance, freshly require the disk hash to equal `writtenHash`, then
call `mark-done.sh`. A mismatch is a collision and blocks the tier; it is never
silently skipped. This reconciliation is idempotent and is the only legal recovery
for that crash window.

**Tier input comes from `write-state.json`, never from `doc-plan.yaml`.** The plan
lists what was _wanted_; the queue records what was _approved_. Re-deriving tier
inputs from the plan reintroduces every path the collision step refused, which is
exactly the failure this queue exists to prevent.

Ask the state-agent for the tier's slice:

```
tier N input = writeQueue filtered to provenance[path].tier == N
                            and to provenance[path].writeStatus == "pending"
```

The `pending` filter is what makes a replay affordable and safe. Without it, re-entering
a tier would hand every file in that tier back to a writer — including files this run
already finished, whose bytes no longer hash to their `scaffoldHash`. Those files would
be rewritten from scratch at best, and refused by the provenance guard at worst. With
it, a replayed tier processes exactly the paths the transition put back into `pending`:
the new gap files and the paths that link to them.

Note the input is `writeQueue` + `provenance` + `pending` status only. Tier and queue
membership are never re-derived from `doc-plan.yaml`, on a first pass or on a replay.

If the computed input set is empty, the tier has nothing to do: record it complete and
advance without initializing a processor state.

Pipe that list — and only that list — into init-state.sh:

```bash
# Tier N paths come from the durable approved queue, not from doc-plan.yaml
<tier-N-queue-slice> | bash docs/standards/contributor-docs/scripts/init-state.sh \
  .contributor-docs/write-tier-N/state.json \
  '<source-paths-json>' \
  <concurrent-agents> \
  '.contributor-docs/write-tier-N/findings'
```

Reuse an existing `.contributor-docs/write-tier-N/state.json` **only if its file set is
exactly the computed tier input** (resumability). On any difference — extra files, missing
files, or a state left behind by an earlier pass — re-initialize from scratch. "It exists
and something is still pending" is not evidence that it describes the current queue; after
a gap transition it usually does not, which is why the transition deletes the processor
state for every tier it resets before it clears itself.

### 2. Process Loop

```
while next-file.sh returns files:
  1. Get next batch: bash docs/standards/contributor-docs/scripts/next-file.sh .contributor-docs/write-tier-N/state.json --batch <N>
  2. For each file in batch, spawn a doc-writer team agent (sonnet):
     - Tell it to read docs/standards/contributor-docs/write/write-file.md
     - Provide: file path, type, description, sources, crossLinks from doc-plan.yaml
     - Provide: the tier number
  3. Wait for all agents in batch to complete.
  4. For each successful report, require lowercase 64-hex
     `AUTHORIZED_FROM_HASH` and `WRITTEN_HASH` values.
  5. Spawn state-agent `record-write`. It freshly hashes the file, requires equality
     with `WRITTEN_HASH`, atomically records `writeStatus: "written"` plus that exact
     `writtenHash`, derives `filesWritten`, and consumes any writer-replay approval.
     A mismatch remains pending; state-agent `record-writer-collision` persists the
     observed and expected hashes in `blockedCollisions`, which blocks dispatch.
  6. Only after `record-write` succeeds, run:
     bash docs/standards/contributor-docs/scripts/mark-done.sh .contributor-docs/write-tier-N/state.json <filename>
```

The order is canonical state first, processor state second. Reversing it can make a
file disappear from the processor while provenance still says pending. The chosen
order has one recoverable crash window, handled by initialization reconciliation.
An outside edit between the writer's return and the fresh state-agent hash therefore
cannot be blessed as workflow output.

When the user approves a writer collision, `approve-writer-replay` first re-hashes the
path and requires equality with the recorded `observedHash`, appends one unconsumed
approval for that exact snapshot, and atomically removes the collision. A changed
snapshot is remeasured and stays blocked. The next writer consumes the approval only
after `WRITTEN_HASH` is freshly verified.

### 3. Tier Complete

When all files in the tier are processed, invoke state-agent `complete-tier N`. It
freshly verifies that:

- the processor has no pending path;
- every queued path assigned to tier N has `writeStatus: "written"` and a valid
  `writtenHash`;
- every such file's current bytes still hash to that `writtenHash`; and
- `filesWritten` equals the derived global count.

Only then does one atomic update append N to `tiersCompleted` and advance the step.
For N < 6 it sets `currentTier: N+1` and `step: "write_tier_{N+1}"`. For N = 6 it
keeps `currentTier: 6` and sets `step: "completed"`; completed state requires
`tiersCompleted == [1, 2, 3, 4, 5, 6]`, every queue entry written, and
`filesWritten == filesTotal`.

`filesWritten` is derived because an incremented counter and a replay disagree
immediately: a replay rewrites files that were already counted, and every gap would
inflate the total past `filesTotal`. Deriving from provenance means the counter cannot
drift from the thing it counts, and a crash between two updates cannot double-count.

If the tier produced gap reports, the tier boundary is also where **all** reports are
collected and de-duplicated — see [Discovered-Gap Transition](#discovered-gap-transition).
Open one transition containing every reporter **before** `complete-tier`; the
transition itself sets the step it replays into.

## Context Provided to Each Doc-Writer

Each spawned doc-writer receives controlled context (see `docs/standards/contributor-docs/common/writing-order.md` for rationale):

| Input                                                | How to Provide                                                          |
| ---------------------------------------------------- | ----------------------------------------------------------------------- |
| The scaffolded file (frontmatter + one-line summary) | Read from disk, include in prompt                                       |
| Frontmatter of all cross-referenced files            | Read `crossLinks` paths from scaffolded files, extract frontmatter only |
| Relevant source code files                           | Read `sources` from doc-plan.yaml entry                                 |
| Current stamped audit errors (repair replay only)    | Read only errors that named this path in the failed audit epoch         |
| Complete normalized planned-path set                 | Re-read current `doc-plan.yaml` immediately before writer dispatch      |
| Module overview content (if tier > 1)                | Read module's `overview.mdx`                                            |
| Body template for the section type                   | From `docs/standards/contributor-docs/common/templates.md`              |
| Formatting checklist                                 | From `docs/standards/contributor-docs/checklist.md`                     |

Writers do NOT receive the full content of other doc files.

## Parallel Within Tiers, Sequential Across Tiers

Within a single tier, all files are written in parallel (batched by concurrent agent count). Across tiers, the order is strict. See `docs/standards/contributor-docs/common/writing-order.md` for the dependency rationale.

## Discovered-Gap Transition

A writer in tier N may find that a concept or algorithm it needs to link to was never
planned. This section is the **authoritative mechanism** for what happens next: the
statuses, the durable effects, the computations, and the refusals.
`docs/standards/contributor-docs/common/writing-order.md#discovered-gaps` owns the
_rationale_ — why the orchestrator holds this transition and why the re-scaffold is
scoped — and links here for the mechanism. Neither document repeats the other's half;
this table exists in exactly one place, and a consistency check proves it.

### The Transition Record

`gapTransition` is null in the ordinary case. While a transition is in flight it is:

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

`reports` is the normalized, de-duplicated batch of every writer report collected at
the tier boundary. Each `reportedBy` must be a queued path in the current tier, each
nested gap must retain its non-empty reason and appear in the top-level `gapPaths`
union, and that union may contain no unreported path. Retaining the mapping lets
planning add a missing cross-link to the right files; one singular reporter loses
completed writers when two agents
independently discover the same dependency.

**`gapTransition != null` blocks ordinary tier dispatch and is the recovery marker.**
Every run checks it before it looks at `step` (dispatch row 1). Its `status` says
exactly which durable effects have already landed, so a crashed transition is resumed
rather than restarted, and restarting one anyway is harmless because every status is
idempotent.

### The Mechanism

<!-- canonical-block: gap-transition-mechanism -->

| Status       | Advanced by | Durable effect of reaching it                                                                                                                                                                                                                                                                                                                                                                                                                                 | Resume from a crash at this status                                                                                                                                            |
| ------------ | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| _(opening)_  | state-agent | Validate the aggregated reports and computed closure, then atomically create `status: "enqueued"` with exact `reports`, their `gapPaths` union, `replayTier`, `requeued`, `resetTiers`, empty `expectedScaffold`/`cleanedTiers`, and `openedAt`. Nothing else changes.                                                                                                                                                                                        | The record exists completely or not at all.                                                                                                                                   |
| `enqueued`   | state-agent | After the orchestrator edits `doc-plan.yaml`, verify every gap entry's path/type/tier and verify each reporter's `crossLinks` now contains the paths in its own report. Then atomically set `status: "planned"`.                                                                                                                                                                                                                                              | Re-apply the idempotent plan edits and ask the state-agent to verify them again.                                                                                              |
| `planned`    | state-agent | Scaffolder `prepare` renders but does not write. Validate its exact path/hash/exact-byte manifest, require `expectedScaffold` key coverage to equal `gapPaths`, measure collisions, and atomically install the hashes plus `status: "prepared"`. Any existing path on its first observation is a collision, even if its bytes equal the proposal. On retry, a still-matching unconsumed scaffold approval resolves that observation instead of recreating it. | Re-run prepare while still planned. A collision keeps the status planned; invoke `approve-collision` for an exact-hash decision, then retry this edge.                        |
| `prepared`   | state-agent | Scaffolder `create` re-renders and proves each persisted hash. For each path: absent → write; current hash equal to `expectedScaffold[path]` → adopt a crash-completed create; current hash equal to an unconsumed scaffold approval → overwrite; anything else → record `GAP_COLLISION`. After fresh disk hashes all match, atomically extend queue/provenance, consume approvals, derive totals, and set `status: "scaffolded"`.                            | Re-run create. A path matching `expectedScaffold` is run-owned at this status even though provenance is not installed yet. Invoke `approve-collision` for a blocked mismatch. |
| `scaffolded` | state-agent | Atomically truncate `tiersCompleted` below `replayTier`, set `currentTier`/`step` to the replay tier, restore every `requeued` path to pending while retaining `writtenHash`, derive `filesWritten`, and set `status: "reset"`.                                                                                                                                                                                                                               | Retry at `scaffolded` applies once; observing `reset` proves the atomic edge already committed.                                                                               |
| `reset`      | state-agent | For each not-yet-cleaned tier, delete its processor `state.json` and findings tree, verify both are absent, and only then atomically append that tier to `cleanedTiers`. When exact set equality with `resetTiers` holds, the same operation sets `status: "cleaned"`.                                                                                                                                                                                        | Resume with the first tier not recorded clean. Missing artifacts are already clean; a failed deletion never earns a `cleanedTiers` entry.                                     |
| `cleaned`    | state-agent | Atomically append a copy with `status: "cleared"` and `closedAt` to `gapsResolved`, then set `gapTransition: null`. The append is unique by `openedAt`.                                                                                                                                                                                                                                                                                                       | If the live transition remains, repeat clear; an existing closed record with the same `openedAt` is not duplicated.                                                           |

**The transition is never cleared before cleanup completes.** `cleaned` exists as a
distinct status precisely so that a crash during cleanup resumes cleanup. If the clear
were folded into the reset, a crash midway would leave `gapTransition: null` with a
completed processor state still on disk for a tier that now has pending work — and the
tier initializer, seeing a state file that looks finished, would skip the replayed
files entirely. The gap would be silently unresolved with every counter reporting
success.

### Computing `requeued`, `replayTier` and `resetTiers`

These three are computed once, when the transition is opened, and are then fixed for
its lifetime. All three are mechanical; none of them is a judgement call.

**`requeued`** is every reporting path plus the transitive reverse-dependency closure
of the gap paths, restricted to work that is already queued:

```
G  = the set of gapPaths
R₀ = { every reports[*].reportedBy }
Rₙ₊₁ = Rₙ ∪ { p ∈ writeQueue : crossLinks(p) ∩ (Rₙ ∪ G) ≠ ∅ }
R  = the fixpoint of that iteration
requeued = (R ∩ writeQueue) \ G, plus the index closure below
```

`crossLinks(p)` is read from `p`'s `doc-plan.yaml` entry. This is a **metadata lookup**,
not a membership derivation: which paths exist and may be written still comes only from
`writeQueue`, and every candidate is intersected with it. The iteration is monotone over
a finite queue, so it terminates in at most `writeQueue.length` rounds.

The closure is transitive because dependency staleness is. If a feature links to the new
concept, the feature is stale; if a surface links to that feature, the surface may now
describe it wrongly too. Stopping at direct dependants would leave exactly the
second-order drift the tier order exists to prevent.

**Index closure.** Indexes and navigation entries list the files in their directory, so
they depend on a new file without ever naming it in `crossLinks`. For every path in
`R ∪ G`, add the queued `index.mdx` of that path's directory, and any queued navigation
or index entry whose plan entry lists that directory. These are added to `requeued` the
same way and follow the same rules.

**`replayTier`** = the lowest `tier` among `G ∪ requeued`. Tier order is the whole point:
re-entering above the lowest affected tier would write a dependant before its dependency.

**`resetTiers`** = the sorted distinct tiers of `G ∪ requeued` — every tier that actually
holds a path going back to `pending`. Tiers at or above `replayTier` that hold no
re-queued path are still re-entered by the ordinary march, but their tier input is empty,
so they complete immediately and their files are never touched. This is deliberate
selectivity, not an oversight: resetting a tier means resetting its **processor state**,
never rewriting its contents. A path that is neither new nor a dependant of a new path
keeps `writeStatus: "written"`, keeps its bytes, and never appears in any tier input
again.

### Refusals

| Condition                                                                              | Refusal                  |
| -------------------------------------------------------------------------------------- | ------------------------ |
| Opening while `gapTransition != null`                                                  | `GAP_IN_FLIGHT`          |
| Any reporter is not a normalized queued path in the current tier                       | `GAP_REPORTER_INVALID`   |
| `reports` is empty, a reason is blank, or its nested gap union differs from `gapPaths` | `GAP_REPORT_SET_INVALID` |
| Any path is absolute, escapes `docsRoot`, is duplicated, or has a type/tier mismatch   | `GAP_PATH_INVALID`       |
| `replayTier > currentTier`                                                             | `GAP_TIER_INVALID`       |
| A proposed gap path is already on `writeQueue`                                         | `GAP_ALREADY_QUEUED`     |
| A gap path appears in two or more prior `gapsResolved` entries                         | `GAP_LOOP`               |
| `expectedScaffold` keys differ from the gap set or a value is not a SHA-256            | `GAP_MANIFEST_INVALID`   |
| A gap file lacks exact-hash approval or prepared-hash ownership                        | `GAP_COLLISION`          |
| A requested status skips or reverses the transition graph                              | `GAP_TRANSITION_INVALID` |
| Cleanup is recorded before the exact processor artifacts are absent                    | `GAP_CLEANUP_INCOMPLETE` |

`GAP_LOOP` is the loop guard. A path that has been gap-scaffolded twice and is being
reported missing a third time is not a retry case — it is a planning failure, and
replaying it again would loop forever while every individual step reports success. Stop
and report instead.

### A Writer That Dies Before Reporting

Step 0 of this transition — the writer noticing — has no durable form inside the
writer. Team agents never touch state files
(`docs/standards/contributor-docs/workflow.md`), so a writer that dies before returning
its report leaves its processor path pending and the tier reprocesses it. Writers still
never persist a competing gap record.

If the retry also omits the gap, audit does **not** pretend an unwritten link is broken.
Each fact-check receives the file's sources, exact planned `crossLinks`, and the
complete normalized planned-path set, then compares significant source behavior with
dependency coverage. A missing link to an existing planned path is an ordinary
completeness error. A genuinely unplanned reusable concept or algorithm becomes a
stamped `missing-dependency` error with path, type, tier, and reason. Audit repair
reopens the reporting file through the normal writer guard; only the latter replay
reports a durable gap batch and enters this transition. Thus discovery may be delayed,
but it cannot pass a clean audit merely because no outbound link existed to validate.

## Consistency Checks

The repository-wired control is the `a-contributor-docs-contract` pre-commit hook. Run
its executable directly from the repository root with:

```bash
bash docs/standards/contributor-docs/scripts/init-state.sh --check-write-contract
```

It must end with `Contributor-doc contract controls passed`. The harness parses the
marked canonical blocks and step tables below, then drives fixed healthy and
destructive transition fixtures. A failure arm must return its named discriminator;
merely exiting nonzero is not a catch. The hook runs the same command on every commit.

1. **Field-set equality.** The canonical schema block here and its mirror in
   `docs/standards/contributor-docs/write/state-agent.md` must have identical sorted key
   lists. Both are selected by the `canonical-block: write-state-schema` marker rather
   than by fence position, because both files contain several fenced `json` blocks and a
   range extractor that concatenates two of them yields invalid JSON — a check that always
   errors is a check that asserts nothing.
2. **Record-shape equality.** The `write-provenance-record`,
   `write-approval-record`, `write-collision-record`, `write-audit-repair-record`, and
   `gap-transition-record` blocks have matching field sets in this file and the
   state-agent mirror.
3. **No retired field survives.** The retired mis-ordering of `tiersCompleted` — the same
   two words the other way round — and a generic `errors` field appear nowhere in the
   contributor-docs tree. This check greps for the retired spelling, so this document
   deliberately does not write it out: a consistency check that matches the sentence
   describing it can never reach zero, and would have to be weakened to pass. Note the
   near-miss it guards: the retired name differs from the canonical one only by word
   order, so a careless global replace destroys the correct field.
4. **Legal-step equality** across this file's schema union, its state machine, the ten
   rows in the Step Dispatch table, and the state-agent's validation list — all four
   name the same ten steps. Gap Sub-Dispatch is compared as a separate status set.
5. **No membership re-derivation from the plan.** This is the judgment half, not a
   binary text gate. The harness prints `REVIEW_REQUIRED` with the complete count of
   surviving `doc-plan.yaml` references under `write/`; a reviewer reads every hit and
   affirms that it is a metadata lookup (`sources`, `crossLinks`, `description`, `type`,
   or `tier` of a _planned_ entry), never a source of queue or tier membership. The
   command neither auto-passes nor auto-fails this semantic classification.
6. **The mechanism table appears exactly once** across the contributor-docs tree —
   selected by its `canonical-block: gap-transition-mechanism` marker.
7. **Negative transition controls.** The executable reducer drives and requires the
   specific refusal discriminator for an initial
   scaffold create before prepare, a completed step with pending queue members, every
   skipped gap status, an incomplete `expectedScaffold` key set, fabricated cleanup,
   and a writer report whose returned hash differs from fresh disk bytes. Then drive
   one healthy initial scaffold and the complete
   `enqueued → planned → prepared → scaffolded → reset → cleaned → cleared` gap path.

## State Transitions

All state writes go through the **write state-agent** (sub-agent, haiku). Read `docs/standards/contributor-docs/write/state-agent.md` for the protocol.

**Bootstrap exceptions:** None.

## Phase Completion

When all tiers are complete:

1. Invoke state-agent `advance-task-phase-to-audit`; never issue a generic task-state
   update. On an initial write it validates the complete step and live hashes before
   moving task phase. Both routes require the canonical source snapshot still current.
   On an audit repair it first commits the matching
   `auditRepair: completed` marker, then moves task phase, and a crash between those
   renames retries only the phase handoff.
2. Proceed to audit phase.
