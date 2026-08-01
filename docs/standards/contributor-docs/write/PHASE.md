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
  "authorizedPlanHash": "<64 lowercase hex>",
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

This is the **canonical write-phase schema** — fourteen top-level fields, and this file
is their single source of truth. The write state-agent's create, assess, update and
gap modes operate on exactly these fields: no more, no fewer, and an unknown field is
refused rather than merged. The state-agent mirrors this block verbatim; where the two
ever disagree, this file takes precedence and the mirror is repaired here first.

`authorizedPlanHash` is initialized from the immutable user-approved
`plan-state.json.planHash`. It can advance only through `apply-gap-plan` after an exact
successor was recorded by `authorize-gap-plan`; no scaffold, writer, audit, repair, or
terminal operation may write it.

Creation requires the exact completed approved seven-field plan state, task phase
`write`, matching task/plan paths equal to `.contributor-docs/doc-plan.yaml`, the
current bound source/diff-summary snapshot, and a fresh live-plan hash equal to the
approved `planHash`. The initial `authorizedPlanHash` is copied from that hash, never
provided by a caller. A candidate sidecar must be absent on this no-gap baseline.

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
    "writtenHash": null,
    "writerReport": null
  }
}
```

Preparation records `scaffoldHash` before any bytes are created and leaves
`scaffoldedAt: null`. Finalization freshly hashes the file and fills `scaffoldedAt`
only after the current bytes match that prepared hash. No tier may run while any
queued provenance entry still has a null `scaffoldedAt`.

A successful `record-write` replaces `writerReport: null` with this exact record in the
same atomic write that installs `writeStatus: "written"` and `writtenHash`:

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

`GAPS: none` becomes an empty `gaps` array, never a null report. The record binds the
reporter and every exact gap tuple/reason to the plan authority, pre-write bytes, and
written bytes that `record-write` independently verified. A path is `written` only when
this complete report is non-null. Any operation that restores it to `pending` clears
`writerReport` in the same state rename while retaining `writtenHash` as replay
authority; the live or closed gap transition already retains any report it consumed.

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

**`writtenHash` and `writerReport` are recorded whenever a writer completes**, in the
same state update that sets `writeStatus: "written"`. The writer must report both, and
the state-agent freshly hashes the disk and plan and validates the complete structured
gap set before installing any of them. On a replay the transition sets `writeStatus`
back to `pending`, clears `writerReport`, and
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

| #   | Condition                                                     | Action                                                                                                                                                                      |
| --- | ------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `sourceSnapshotCurrent: false`                                | Report `SOURCE_DRIFT_BLOCKED` with exact drift evidence and mutate nothing                                                                                                  |
| 2   | Exact valid `enqueued` tuple and `gapPlanApplyRequired: true` | Invoke only `apply-gap-plan`, including adoption of the one candidate-rename crash tuple; dispatch nothing else                                                             |
| 3   | Write state exists and `planHashCurrent: false`               | Report `PLAN_DRIFT_BLOCKED: expected=<hash> actual=<hash-or-absent>` and mutate no state, processor, task-phase, or audit artifact bytes                                    |
| 4   | `gapTransition != null`                                       | **Finish the in-flight transition first** — resume its exact operation from `status`. No initial scaffold or tier may run.                                                  |
| 5   | No `write-state.json`                                         | Create via state-agent with `step: "scaffold"` and approved `authorizedPlanHash`, then reassess                                                                             |
| 6   | `blockedCollisions` nonempty                                  | Present every measured collision; invoke `resolve-scaffold` at `scaffold_blocked` or `approve-writer-replay` in a write tier; dispatch no writer until the exact set clears |
| 7   | `step: "scaffold"`                                            | Spawn scaffolder `prepare`, input set = the whole plan; invoke `prepare-scaffold` on its complete manifest                                                                  |
| 8   | `step: "scaffold_blocked"`                                    | Invalid without collisions — state-agent reports the broken invariant                                                                                                       |
| 9   | `step: "scaffold_prepared"`                                   | Spawn scaffolder `create`, input set = prepared `writeQueue`; invoke `block-scaffold` for any mismatch, otherwise `finalize-scaffold`                                       |
| 10  | `step: "write_tier_N"`                                        | Reconcile canonical written records with processor state, then run the file-processor loop for tier N                                                                       |
| 11  | `step: "completed"`                                           | Invoke state-agent `advance-task-phase-to-audit`; do not issue a generic phase update                                                                                       |

Source drift takes precedence over every write or recovery action. The sole next
exception is a completely validated `enqueued` `apply-gap-plan` tuple, because its
candidate-to-live rename may have committed before the state rename. Ordinary plan
drift then preempts every remaining in-flight gap, scaffold, processor, writer,
repair, collision, tier-completion, and task-phase operation. A transition whose plan
identity is current still outranks the ordinary step because the step is not yet true
of its partially applied queue effects.

`planHashCurrent: true` is an immediate precondition for every ordinary scaffolder or
writer dispatch, processor reconciliation, collision decision, `prepare-scaffold`,
`resolve-scaffold`, `block-scaffold`, `finalize-scaffold`, audit-repair reopen/resume,
`record-writer-collision`, `approve-writer-replay`, `record-write`, `complete-tier`,
and `advance-task-phase-to-audit`. Mode 3 requires the same guard on every edge and
collision decision except the narrowly fenced `apply-gap-plan` crash tuple. The guard
is freshly re-evaluated at state-agent acceptance, not inherited from an earlier
assessment.

Before `write-state.json` exists there is no authority chain to assess. The no-state
row therefore invokes `create`, whose single validation point independently requires
the immutable approved root, current live-plan hash, and absent candidate before it
copies that root into `authorizedPlanHash`; failed creation cannot bypass the drift
guard.

## Initial Scaffold Protocol

Initial scaffolding is a durable prepare → create → finalize protocol. A one-shot
"create, then report" is forbidden: a crash after the filesystem write but before the
state write would leave an ownerless file that the retry correctly treats as a
collision.

Every scaffolder dispatch receives `PLAN_SHA256 = authorizedPlanHash`. Immediately
before consuming plan metadata and again before returning a prepare/create report, the
scaffolder hashes the exact live plan and requires equality. Its report carries the
same `PLAN_SHA256`; the accepting state-agent freshly rehashes the live plan and
requires the report and state authority to match. Any mismatch is
`PLAN_DRIFT_BLOCKED`, not a scaffold collision.

### 1. Prepare — `prepare-scaffold`

The scaffolder classifies the **entire** whole-plan input, renders the exact bytes for
each proposed scaffold in memory, and returns a machine-readable manifest containing
path, tier, disposition, exact bytes, SHA-256, and (for a collision) the current hash
and line count. It writes nothing.

The state-agent validates exact input coverage, normalized root-relative paths under
`docsRoot`, every reported hash, and the returned `PLAN_SHA256`. The orchestrator
invokes `prepare-scaffold`,
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
the render hash to equal `provenance[path].scaffoldHash`. It also rechecks
`PLAN_SHA256` before rendering and before returning. It then applies exactly one of
these rules:

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
the current epoch. Before any recovery mutation it requires the complete plan-authority
chain and fresh live plan hash to be current. It validates that every selected path:

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
`plannedPaths` set, read only after the live plan hashes to `authorizedPlanHash`, at
dispatch time. A stamped
`missing-dependency` error whose proposed path is absent from that set must be returned
in the writer's `GAPS` report so the normal discovered-gap transition adds and replays
the dependency. If its proposed path has since joined `plannedPaths`, the writer
downgrades the retained error to an ordinary link-only repair and produces no gap item.

After all tiers reach `completed`, `advance-task-phase-to-audit` freshly validates the
marker's epoch/digest, the complete plan-authority chain, every marked path's written
status, and every live `writtenHash`. It first changes the marker to `completed`, then moves task phase
`write → audit`. A crash between those renames is an idempotent retry: the completed
marker authorizes only finishing the task-phase rename. The marker — not task phase or
the still-failed audit counters alone — proves that a writer-authorized repair cycle
finished. Only then may audit reset to a fresh epoch. No direct document edit, stale
`writtenHash`, or completed processor cache can bypass this replay.

## File-Processor Loop (Per Tier)

For each `write_tier_N` step:

### 1. Initialize

Before computing new input, invoke the state-agent's read-only
`authorize-processor-init`. It performs the complete source and plan-authority guard,
requires no live gap/candidate or collision, and returns both the exact current-tier
pending slice and `authorizedPlanHash`; it never accepts either from the caller. Pass
that hash to every processor helper as `--plan-hash`.

Then reconcile processor state with canonical provenance. A
crash may occur after the state-agent records a verified write but before
`mark-done.sh` updates the processor. For each processor-pending path already marked
`written` in provenance, require a complete non-null `writerReport`, freshly require
the disk hash to equal `writtenHash`, invoke read-only
`authorize-processor-complete`, then call `mark-done.sh` with the returned hash. A
missing report is `GAP_REPORT_SET_INVALID`; a byte mismatch is a collision. Either
blocks the tier and is never silently skipped. This reconciliation is idempotent and
is the only legal recovery for that crash window.

Reconciliation begins only after a fresh live-plan hash equals
`authorizedPlanHash` and the complete plan-mutation chain validates. Processor state
cannot hide plan drift.

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

If the state-agent-derived input set is empty, the tier has nothing to do: record it
complete and advance without initializing processor state. The read-only authorization
still runs; an unfenced caller may not declare a tier empty.

Pipe that list — and only that list — into init-state.sh:

```bash
# Tier N paths come from the durable approved queue, not from doc-plan.yaml
<tier-N-queue-slice> | bash docs/standards/contributor-docs/scripts/init-state.sh \
  .contributor-docs/write-tier-N/state.json \
  '<source-paths-json>' \
  <concurrent-agents> \
  '.contributor-docs/write-tier-N/findings' \
  --plan-hash '<authorizedPlanHash returned by authorize-processor-init>'
```

Every write-tier processor persists the exact ordered operation snapshot below. Its
object keys, in insertion order, equal `filesToProcess`; there is one entry for every
and only every pending tier path:

```json
{
  "recordWriteAuthorizations": {
    "docs/contributor/orders/features/checkout.mdx": {
      "normalHash": "<retained writtenHash, otherwise scaffoldHash>",
      "replayApproval": {
        "ledgerIndex": 3,
        "approvedHash": "<exact unconsumed writer-replay approval hash>"
      }
    }
  }
}
```

`replayApproval` is `null` when none applies. Initialization derives the sole
unconsumed approval's stable append-only array index and hash; multiple applicable
approvals or a malformed hash refuse initialization. This snapshot is not new
canonical write authority: it is bound to the processor's `authorizedPlanHash`, tier,
and exact file list so completion can prove the pre-write authority after canonical
provenance has changed. Shared fact-check processors store
`recordWriteAuthorizations: null`. A write-tier processor missing the field is a stale
legacy cache and must be removed and reinitialized; authority is never inferred.

Reuse an existing `.contributor-docs/write-tier-N/state.json` **only if its file set is
exactly the computed tier input, its `authorizedPlanHash` equals the freshly returned
authority, and its authorization map exactly matches the durable snapshot captured at
that initialization** (resumability). On any difference — extra files, missing files,
stale plan authority, missing/legacy map, or a state left behind by an earlier pass —
re-initialize from scratch. "It exists and something is still pending" is not evidence
that it describes the current queue; after a gap transition it usually does not, which
is why the transition deletes the processor state for every tier it resets before it
clears itself.

Both helpers participate in the canonical
[Authority Transaction](../workflow.md#authority-transaction). `init-state.sh`
re-derives the exact ordered pending slice and authorization map under the lock;
`mark-done.sh` applies the same committed writer-report law described below. Each
captures exact authority and processor preimages, reruns the semantic fence after
staging, and compares both preimages immediately before its `mv`. A changed slice,
tier, collision, ledger, authority byte, assigned document, or processor preimage is
`PROCESSOR_AUTHORITY_INVALID` (with plan/byte drift retaining its more specific
precedence). `AUTHORITY_BUSY` is a fail-fast retry outcome and changes nothing.
The byte fingerprints close the window from an operation's first authority read
through its last authority read. The residual interval between that last read and `mv`
is closed by the exclusive advisory lock every compliant writer takes, not by the
rename itself. An out-of-contract same-user writer in that residual interval is not
prevented. A later mandatory assessment detects only surviving authority or document
drift; a raw write to the processor target that the ordinary `mv` overwrites can be
undetectable and is outside the contract.

### 2. Process Loop

```
while next-file.sh returns files:
  1. Get next batch: bash docs/standards/contributor-docs/scripts/next-file.sh .contributor-docs/write-tier-N/state.json --batch <N>
  2. For each file in batch, spawn a doc-writer team agent (sonnet):
     - Tell it to read docs/standards/contributor-docs/write/write-file.md
     - Provide: file path, type, description, sources, crossLinks from doc-plan.yaml
     - Provide: the tier number
     - Provide: `PLAN_SHA256 = authorizedPlanHash`
  3. Wait for all agents in batch to complete.
  4. Classify each writer report before accepting success:
     - `ERROR: AUTHORITY_BUSY` is neither a file failure nor a malformed report. Keep
       that path's `writeStatus: "pending"`; do not invoke `record-write`, record no
       collision, and re-dispatch the untouched pending path in the next batch.
       `next-file.sh` already selects pending paths, so it needs no special path
       handling. Cap that re-dispatch at three passes per path per tier. On exhaustion,
       stop the tier and report the busy outcome without marking the path failed or
       written. `AUTHORITY_BUSY` is distinct from `PLAN_DRIFT_BLOCKED` and from a
       writer collision.
     - For each successful report, require lowercase 64-hex `PLAN_SHA256`,
       `AUTHORIZED_FROM_HASH`, and `WRITTEN_HASH` values. The writer must have hashed
       the exact plan before consuming metadata and again immediately before its
       authorized write/report.
  5. Spawn state-agent `record-write`. While holding the Authority Transaction lock,
     invoke the shared `init-state.sh --assert-record-write pending` law before
     candidate construction and again after staging, before its final preimage recheck
     under the compliant-writer lock and ordinary atomic rename.
     The law freshly hashes the file, requires equality
     with `WRITTEN_HASH`, freshly hashes the live plan and requires equality with both
     reported `PLAN_SHA256` and `authorizedPlanHash`, validates the complete structured
     `GAPS` field, and atomically records `writeStatus: "written"`, that exact
     `writtenHash`, and the bound five-field `writerReport`. The same rename derives
     `filesWritten` and consumes any writer-replay approval. A file or malformed-report
     mismatch remains pending. Its returned branch is exactly `normal` or
     `approval:<ledgerIndex>`; only the latter consumes that exact approval in the same
     canonical rename;
     state-agent `record-writer-collision` persists the observed and expected hashes in
     `blockedCollisions`, which blocks dispatch. A plan mismatch is instead the
     non-mutating `PLAN_DRIFT_BLOCKED` outcome.
  6. Only after `record-write` succeeds, invoke state-agent
     `authorize-processor-complete` for that exact path, then run `mark-done.sh`. The
     helper invokes the same law in `committed` view: a selected approval must now be
     consumed, while the normal branch must not have consumed it.
     bash docs/standards/contributor-docs/scripts/mark-done.sh .contributor-docs/write-tier-N/state.json <filename> --plan-hash '<returned authorizedPlanHash>'
```

The canonical `--assert-record-write` invocation and its pending-view stdin object are
documented once in `docs/standards/contributor-docs/write/state-agent.md`; this phase
relies on that block rather than duplicating it.

The order is canonical state first, processor state second. Reversing it can make a
file disappear from the processor while provenance still says pending. The chosen
order has one recoverable crash window, handled by initialization reconciliation.
The complete gap report is already durable before that window, and `mark-done.sh`
independently repeats the full chain/live-hash check immediately before its atomic
rename. An outside edit or plan change between the writer's return and either fresh
check therefore cannot be blessed as workflow output or processor completion.

The pending and committed views are one predicate, not two similar validators. It
requires the exact five writer-report keys; a normalized reporter and every gap path
strictly below normalized non-root `task-state.docsRoot`; and an actual regular
reporter whose resolved path remains below the resolved docs root (including existing
parent symlinks). The current processor path/tier/file list, write queue/provenance,
plan hash, empty collision set, and null gap must agree. Plan, start, and written hashes
are lowercase SHA-256 values; the written hash equals returned bytes, fresh disk bytes,
and committed provenance as applicable. Every gap has exactly path/type/tier/reason,
a nonblank reason, concept→2 or algorithm→3, a unique tuple, and no conflicting
metadata for one path. `authorizedFromHash` equals either the snapshot's `normalHash`
or its exact approval index/hash. Pending view requires that approval unconsumed and
normal authority still equal to current pending provenance; committed view requires a
selected approval consumed and a normal-branch approval still unconsumed. Missing
snapshot authority is `PROCESSOR_AUTHORITY_INVALID`; malformed or escaped report data
is `GAP_REPORT_SET_INVALID`. A pending report/disk hash mismatch is
`WRITE_HASH_MISMATCH`; an incomplete lifecycle record is `WRITE_INCOMPLETE`; and
post-commit drift from the recorded document bytes is `WRITTEN_BYTES_CHANGED`.

When the user approves a writer collision, `approve-writer-replay` first re-hashes the
path and requires equality with the recorded `observedHash`. Under one Authority
Transaction it removes and verifies absent the current tier processor state/findings
before appending the unconsumed approval and removing the collision. Cleanup-first is
safe if the process crashes; retry repeats it. Reinitialization then captures the new
stable ledger index/hash, so a stale processor cannot acquire a later approval. A
changed snapshot is remeasured and stays blocked. The next writer consumes the
approval only after `WRITTEN_HASH` is freshly verified.

### 3. Tier Complete

When all files in the tier are processed, invoke state-agent `complete-tier N`. It
freshly verifies that:

- the complete plan-authority chain is valid and the live plan hashes to
  `authorizedPlanHash`;
- the processor has no pending path;
- every queued path assigned to tier N has `writeStatus: "written"`, a valid
  `writtenHash`, and a complete non-null `writerReport` bound to that path, plan, and
  written hash;
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

At the tier boundary, the state-agent derives the complete sorted report batch only
from current-tier `provenance[*].writerReport` records whose `gaps` arrays are non-empty.
It never collects from agent transcripts or caller memory. If that durable ledger
produced gaps, open one transition containing every reporter **before**
`complete-tier`; the transition itself sets the step it replays into.

## Context Provided to Each Doc-Writer

Each spawned doc-writer receives controlled context (see `docs/standards/contributor-docs/common/writing-order.md` for rationale):

| Input                                                | How to Provide                                                          |
| ---------------------------------------------------- | ----------------------------------------------------------------------- |
| The scaffolded file (frontmatter + one-line summary) | Read from disk, include in prompt                                       |
| Frontmatter of all cross-referenced files            | Read `crossLinks` paths from scaffolded files, extract frontmatter only |
| Relevant source code files                           | Read `sources` from doc-plan.yaml entry                                 |
| Authorized plan identity                             | Pass `PLAN_SHA256 = authorizedPlanHash`                                 |
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

The nested plan authority is exactly this five-field record:

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

`reports` is the normalized, sorted batch the state-agent derives at the tier boundary
only from written current-tier provenance records whose bound `writerReport.gaps` is
non-empty. A caller cannot supply or narrow it. Each `reportedBy` is the provenance key
and each nested gap retains the exact normalized `path`, `type`, `tier`, and non-empty
`reason` committed by `record-write`. The state-agent derives `gapPaths` by
de-duplicating those exact
`(path, type, tier)` tuples; a path reported with conflicting type or tier is refused,
and the derived array may contain no unreported path. Retaining the complete mapping
lets the candidate add a missing cross-link to the right files; one singular reporter
loses completed writers when two agents independently discover the same dependency.

`entry` is the complete parsed YAML mapping added to the candidate, including every
optional key and value. `container` is a stable selector such as `module:<name>` or
`shared`, never an array index. Under `LC_ALL=C`, `addedPlanEntries` is sorted by
`outputPath` and `addedCrossLinks` by `(reportedBy, field, target)`. Every live
transition and every closed `gapsResolved` record carries this complete
`planMutation` unchanged.

### Candidate Authorization and Exact Delta

The orchestrator may write only
`.contributor-docs/doc-plan.gap-candidate.yaml`. That sidecar is transient, is not the
live plan, and grants no authority merely by existing. The state-agent parses both the
current live plan and candidate and independently derives `planMutation`; a caller may
not supply or narrow the delta.

`authorize-gap-plan` is the sole operation allowed to inspect a candidate while no
live transition exists. Its input window is the narrow exception to the resting
no-gap rule that the sidecar is absent: the closed-chain cursor, live hash, and
`authorizedPlanHash` must still match, and the operation either atomically records the
complete authority or refuses without touching either plan.

`authorize-gap-plan` accepts only this exact semantic delta:

1. Candidate-only normalized output paths equal the `gapPaths` independently derived
   from the durable reports exactly.
2. Every added entry's normalized output path, `type`, and `tier` equal its gap item;
   its complete mapping is captured in `addedPlanEntries`, and the entire candidate
   passes ordinary complete-plan validation for `docsRoot`, path, type/tier, sources,
   and links.
3. Additions to existing entries are exactly the reporter-to-gap edges in `reports`,
   under `concepts` for concept gaps or `algorithms` for algorithm gaps.
4. No existing scalar, source, tag, description, module metadata, entry, or unrelated
   link changes; no key or entry is removed; no extra entry or link appears.
5. `fromPlanHash` equals both a fresh live-plan hash and
   `write-state.authorizedPlanHash`. `toPlanHash` is a fresh SHA-256 of all candidate
   bytes and must differ from `fromPlanHash`.

The endpoint hashes bind raw bytes; the stored parsed delta proves that the authority
is no wider than the reported gaps.

### Plan-Authority Chain

Every assessment and every write/audit operation validates the full chain, never just
the latest field:

1. Set `cursor = plan-state.planHash` after completely validating the immutable
   completed approved plan state.
2. Before walking hashes, require every `gapsResolved` item to have the complete ten
   transition fields plus `closedAt`, status `cleared`, valid complete report/reason and
   gap-tuple evidence, unique reporters and tuples, the exact reporter/requeue/reset
   relationships, complete cleanup evidence, and typed, sorted added-entry/link
   evidence equal to the reported gaps. Reconstruct that record's open-time link graph
   and queue, then require `requeued`, `replayTier`, and `resetTiers` to equal the
   mechanically re-derived values exactly. Require an `openedAt` unique across the log.
   A malformed history is `GAP_CLOSURE_INVALID`.
3. Walk those records in append order. Require each
   `planMutation.fromPlanHash == cursor`, then advance `cursor` to `toPlanHash`.
4. With no live gap, require
   `cursor == authorizedPlanHash == SHA256(live doc-plan.yaml)` and require the
   candidate sidecar absent.
5. With a live gap at `planned|prepared|scaffolded|reset|cleaned`, require its
   `fromPlanHash == cursor`, then require
   `toPlanHash == authorizedPlanHash == SHA256(live plan)`; the candidate is absent and
   the derived cursor advances to `toPlanHash`.
6. The sole exceptional tuple is `enqueued` with fully valid stored authority:
   `authorizedPlanHash == fromPlanHash == cursor`. The live hash may be
   `fromPlanHash` with an exact `toPlanHash` candidate present, or `toPlanHash` with
   the candidate absent after the candidate rename landed but before the state rename.

Outside that fenced recovery tuple, an absent plan, broken lineage, or live hash that
differs from `authorizedPlanHash` is the non-mutating
`PLAN_DRIFT_BLOCKED: expected=<hash> actual=<hash-or-absent>` outcome.

**`gapTransition != null` blocks ordinary tier dispatch and is the recovery marker.**
After source drift, the one valid `enqueued` plan-apply tuple is checked before ordinary
plan drift; all other live transitions are checked only after plan identity is current.
Its `status` says exactly which durable effects have already landed, so a crashed
transition is resumed rather than guessed at.

### The Mechanism

<!-- canonical-block: gap-transition-mechanism -->

| Status       | Advanced by          | Durable effect of reaching it                                                                                                                                                                                                                                                                                                                                                                                                                | Resume from a crash at this status                                                                                                                                               |
| ------------ | -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| _(opening)_  | `authorize-gap-plan` | Require current source and plan authority, validate reports and closure, parse and completely validate the current/candidate plans, and independently prove the exact delta. Atomically create `status: "enqueued"` with the complete `planMutation`, reports, computed fields, empty `expectedScaffold`/`cleanedTiers`, and `openedAt`. The live plan and `authorizedPlanHash` do not change.                                               | With no record, repair or recreate only the candidate sidecar and retry authorization. An installed record is complete; never synthesize it from candidate existence.            |
| `enqueued`   | `apply-gap-plan`     | Accept only the stored authority. Normally atomically rename the exact candidate over `doc-plan.yaml`, freshly prove `toPlanHash`, then atomically set `authorizedPlanHash = toPlanHash` and status `planned` in the same write-state rename. If live already hashes to `toPlanHash` and the candidate is absent, adopt that one rename crash by performing only the state update. Observing planned/to is idempotent success.               | A live `fromPlanHash` needs the exact candidate. A live `toPlanHash` with no candidate finishes only the pending state rename. Every other tuple is refused without a new write. |
| `planned`    | state-agent          | With the candidate absent and live/authorized hash equal to `toPlanHash`, scaffolder `prepare` validates `PLAN_SHA256`, renders but does not write, and returns an exact-byte manifest. Validate exact `gapPaths` coverage, measure collisions, and atomically install `expectedScaffold` plus status `prepared`. Any existing path on first observation is a collision; a still-matching unconsumed scaffold approval resolves it on retry. | Re-run prepare while still planned. A collision keeps the status planned; invoke `approve-collision` for an exact-hash decision, then retry this edge.                           |
| `prepared`   | state-agent          | With plan identity still current, scaffolder `create` re-renders and proves every persisted hash and `PLAN_SHA256`. For each path: absent → write; expected scaffold hash → adopt a crash-completed create; exact unconsumed scaffold approval → overwrite; anything else → `GAP_COLLISION`. After fresh disk hashes match, atomically extend queue/provenance, consume approvals, derive totals, and set status `scaffolded`.               | Re-run create. A path matching `expectedScaffold` is run-owned at this status even though provenance is not installed yet. Invoke `approve-collision` for a blocked mismatch.    |
| `scaffolded` | state-agent          | After revalidating the full plan chain, atomically truncate `tiersCompleted` below `replayTier`, set `currentTier`/`step` to the replay tier, restore every `requeued` path to pending while retaining `writtenHash` and clearing `writerReport`, derive `filesWritten`, and set status `reset`.                                                                                                                                             | Retry at `scaffolded` applies once; observing `reset` proves the atomic edge already committed.                                                                                  |
| `reset`      | state-agent          | After revalidating plan identity, delete each not-yet-cleaned tier's processor state/findings, verify absence, and only then atomically append that tier to `cleanedTiers`. Exact equality with `resetTiers` sets status `cleaned` in the same write.                                                                                                                                                                                        | Resume with the first tier not recorded clean. Missing artifacts are already clean; a failed deletion never earns a `cleanedTiers` entry.                                        |
| `cleaned`    | state-agent          | After revalidating plan identity, atomically append all ten transition fields, including reports/reasons and unchanged `planMutation`, with status `cleared` and `closedAt` to `gapsResolved`, then set `gapTransition: null`. Validate the complete eleven-field record and unique `openedAt` before writing.                                                                                                                               | If the live transition remains, repeat clear; the exact existing closed record with this `openedAt` is not duplicated. Malformed or conflicting history is refused.              |

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
Rₙ₊₁ = Rₙ
       ∪ { p ∈ writeQueue : crossLinks(p) ∩ (Rₙ ∪ G) ≠ ∅ }
       ∪ indexClosure(Rₙ ∪ G)
R  = the fixpoint of that iteration
requeued = sorted((R ∩ writeQueue) \ G)
```

`crossLinks(p)` is read from `p`'s live `doc-plan.yaml` entry only after that file
freshly hashes to `authorizedPlanHash`. This is a **metadata lookup**, not a membership
derivation: which paths exist and may be written still comes only from `writeQueue`,
and every candidate is intersected with it. The iteration is monotone over a finite
queue, so it terminates in at most `writeQueue.length` rounds.

The closure is transitive because dependency staleness is. If a feature links to the new
concept, the feature is stale; if a surface links to that feature, the surface may now
describe it wrongly too. Stopping at direct dependants would leave exactly the
second-order drift the tier order exists to prevent.

**Index closure.** Indexes list the files in their directory, so they depend on a new
file without naming it in `crossLinks`. At each iteration, for every path newly under
consideration from `Rₙ ∪ G`, add every queued plan entry whose directory is the same
and whose plan metadata declares it as an index: the entry is in the `indexes`
collection or has `type: index`. Ancestor indexes and module overviews are not implied.
Index entries join the same monotone fixpoint as cross-link dependants, so a queued
path that links to an affected index is reached on the next iteration.

Closed-history validation uses the metadata and membership that existed when each
record opened, not today's accumulated successor. Starting from the current authorized
plan and append-only queue, it removes that record's and every later closed record's
`addedCrossLinks` and `gapPaths`, plus the corresponding fields of any live transition.
The reconstruction is exact because gap successors are the only legal plan-growth path,
their complete additions are stored in order, and gap scaffolding is the only operation
that extends `writeQueue`. The record's own reporter-to-gap links may be included or
removed without changing the result because every reporter is already in `R₀`.
The state-agent/reducer performs the additional live-transition subtraction because it
validates ordinary dispatch while a later transition is present. The production
processor helper requires `gapTransition: null`, so its equivalent reconstruction has
no live-transition terms; both copies use the same closed-record suffix rule.

**`replayTier`** equals the lowest `tier` among `G ∪ requeued`; it is not merely bounded
by that value. Tier order is the whole point: re-entering above the lowest affected tier
would write a dependant before its dependency. Because every reporter is a current-tier
queued path and is included in `requeued`, the derived value cannot exceed
`currentTier` **when the transition opens**. A closed historical record is validated
against its stored queue/provenance reconstruction after the live `currentTier` may
have advanced, so it is never compared with today's tier.

**`resetTiers`** = the sorted distinct tiers of `G ∪ requeued` — every tier that actually
holds a path going back to `pending`. Tiers at or above `replayTier` that hold no
re-queued path are still re-entered by the ordinary march, but their tier input is empty,
so they complete immediately and their files are never touched. This is deliberate
selectivity, not an oversight: resetting a tier means resetting its **processor state**,
never rewriting its contents. A path that is neither new nor a dependant of a new path
keeps `writeStatus: "written"`, keeps its bytes, and never appears in any tier input
again.

### Refusals

| Condition                                                                                                         | Refusal                      |
| ----------------------------------------------------------------------------------------------------------------- | ---------------------------- |
| Outside the exact `enqueued` recovery tuple, live plan is absent/mismatched or lineage is invalid                 | `PLAN_DRIFT_BLOCKED`         |
| Any closed record is incomplete, repeats `openedAt`, or differs from its re-derived closure/tier/cleanup metadata | `GAP_CLOSURE_INVALID`        |
| Candidate is absent when `authorize-gap-plan` or a normal `apply-gap-plan` requires it                            | `GAP_PLAN_CANDIDATE_MISSING` |
| Candidate's parsed delta is wider/narrower than the exact reported entries and reporter links                     | `GAP_PLAN_DELTA_INVALID`     |
| Candidate/live bytes do not hash to the stored endpoint required by `apply-gap-plan`                              | `GAP_PLAN_HASH_INVALID`      |
| Opening while `gapTransition != null`                                                                             | `GAP_IN_FLIGHT`              |
| Any reporter is not a normalized queued path in the current tier                                                  | `GAP_REPORTER_INVALID`       |
| `reports` empty, reason blank, type/tier conflicts, or `gapPaths` differs from derived tuples                     | `GAP_REPORT_SET_INVALID`     |
| A written tier path has no complete bound provenance `writerReport`                                               | `WRITE_REPORT_MISSING`       |
| Any path is absolute, escapes `docsRoot`, is duplicated, or has a type/tier mismatch                              | `GAP_PATH_INVALID`           |
| `replayTier > currentTier`                                                                                        | `GAP_TIER_INVALID`           |
| A proposed gap path is already on `writeQueue`                                                                    | `GAP_ALREADY_QUEUED`         |
| A gap path repeats across `gapsResolved`, or a live gap repeats a closed path                                     | `GAP_LOOP`                   |
| `expectedScaffold` keys differ from the gap set or a value is not a SHA-256                                       | `GAP_MANIFEST_INVALID`       |
| A gap file lacks exact-hash approval or prepared-hash ownership                                                   | `GAP_COLLISION`              |
| A requested status skips or reverses the transition graph                                                         | `GAP_TRANSITION_INVALID`     |
| Cleanup is recorded before the exact processor artifacts are absent                                               | `GAP_CLEANUP_INCOMPLETE`     |

Every refusal above leaves write state, the live plan, candidate (except a successful
candidate-to-live rename), processor state, task phase, and audit artifacts
byte-identical. Collision measurement retains its existing narrow exception: it may
atomically replace `blockedCollisions` while leaving the transition status unchanged.

`GAP_LOOP` is the loop guard. A path that has been gap-scaffolded twice and is being
reported missing a third time is not a retry case — it is a planning failure, and
replaying it again would loop forever while every individual step reports success. Stop
and report instead.

### A Writer That Dies Before Reporting

Step 0 of this transition — the writer noticing — has no durable form inside the
writer. Team agents never touch state files
(`docs/standards/contributor-docs/workflow.md`), so a writer that dies before returning
its report leaves its processor path pending and the tier reprocesses it. Writers still
never persist a competing gap record. Once a successful report returns, however,
`record-write` makes its normalized `GAPS` field durable in provenance before the
processor path can be marked done; tier-boundary recovery never depends on a surviving
agent transcript.

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
   `write-writer-report-record`, `write-approval-record`, `write-collision-record`,
   `write-audit-repair-record`, and `gap-transition-record` blocks have matching field
   sets in this file and the state-agent mirror. The nested
   `gap-plan-mutation-record` is compared separately and must have exactly its five
   fields. Every closed record is derived as all ten transition fields plus
   `closedAt`; the hook rejects any truncated copy.
3. **No retired field survives.** The retired mis-ordering of `tiersCompleted` — the same
   two words the other way round — and a generic `errors` field appear nowhere in the
   contributor-docs tree. This check greps for the retired spelling, so this document
   deliberately does not write it out: a consistency check that matches the sentence
   describing it can never reach zero, and would have to be weakened to pass. Note the
   near-miss it guards: the retired name differs from the canonical one only by word
   order, so a careless global replace destroys the correct field.
4. **Legal-step equality** across this file's schema union, its state machine, the ten
   rows in the Step Dispatch table, and the state-agent's marked
   `canonical-block: write-legal-steps` JSON array — all four name the same ten steps.
   Gap Sub-Dispatch is compared as a separate status set.
5. **No membership re-derivation from the plan.** This is the judgment half, not a
   binary text gate. The harness prints `REVIEW_REQUIRED` with the complete count of
   surviving `doc-plan.yaml` references under `write/`; a reviewer reads every hit and
   affirms that it is a metadata lookup (`sources`, `crossLinks`, `description`, `type`,
   or `tier` of a _planned_ entry), never a source of queue or tier membership. The
   command neither auto-passes nor auto-fails this semantic classification.
6. **The mechanism table appears exactly once** across the contributor-docs tree —
   selected by its `canonical-block: gap-transition-mechanism` marker.
7. **Negative transition controls.** The executable reducer proves removal of one
   marked legal step fails with `WRITE_LEGAL_STEP_DRIFT`; ordinary post-approval plan
   tampering blocks both writer dispatch and terminal handoff with
   `PLAN_DRIFT_BLOCKED` and byte-identical state; an exact discovered-gap candidate
   advances through `authorize-gap-plan` and `apply-gap-plan`; an extra semantic delta
   fails with `GAP_PLAN_DELTA_INVALID`; wrong candidate bytes fail with
   `GAP_PLAN_HASH_INVALID`; and the candidate-rename crash tuple is adopted
   idempotently. It parses minimal live/candidate plan bytes and rejects an unrelated
   candidate-byte mutation; validates a complete two-link closed chain and rejects
   reordered, skipped, truncated, duplicate-time, blank-reason, and conflicting-report
   histories; persists writer reports with `record-write`; and refuses unfenced
   processor initialization/completion. Existing controls still cover skipped gap
   statuses, incomplete manifests, fabricated cleanup, collisions, and returned/disk
   writer hash mismatch.
8. **Shared report/authorization controls.** The reducer imports the same jq law used
   by both helpers. Healthy first-write, retained replay, and exact ledger-index
   approval branches pass pending then committed views. Random SHA-shaped start hashes;
   wrong/missing approval index, path, purpose, hash, or consumption state; approval
   reuse; unknown report fields; conflicting gaps; root lookalikes; absolute/dot/parent
   paths; and an existing-parent symlink escape return the named refusal byte-identically.
9. **Authority transaction controls.** Deterministic internal FIFO barriers stop each
   helper after its last semantic check while it owns the lock. A second compliant
   mutator returns `AUTHORITY_BUSY`; after a deliberate raw authority replacement, the
   final preimage check reports `PROCESSOR_AUTHORITY_INVALID` on mismatch before
   processor replacement. The
   manifest covers authority kinds/bytes/absence, processor preimage, and assigned
   document. Two concurrent marks retry to two unique processed paths, a killed holder
   releases without deleting the persistent lock file, and ordinary failure leaves no
   temp file.
10. **Historical reconstruction controls.** Producer output is pinned to the exact
    transitive/index closure and tiers. Two linked closed records make later queue-path
    rollback observable; a closed record plus scaffolded live successor pins live-path
    rollback. Missing later `planMutation`/`gapPaths` returns
    `GAP_CLOSURE_INVALID`, repeated closed/live gap paths return `GAP_LOOP`, and
    unnormalized plan paths/links return `PLAN_DRIFT_BLOCKED` rather than narrowing the
    closure.

## State Transitions

All state writes go through the **write state-agent** (sub-agent, haiku). Read `docs/standards/contributor-docs/write/state-agent.md` for the protocol.

**Bootstrap exceptions:** None.

## Phase Completion

When all tiers are complete:

1. Invoke state-agent `advance-task-phase-to-audit`; never issue a generic task-state
   update. On an initial write it validates the complete step, complete plan-authority
   chain, `authorizedPlanHash`, and all live hashes before moving task phase. Both
   routes require the canonical source snapshot and live plan identity still current.
   On an audit repair it first commits the matching
   `auditRepair: completed` marker, then moves task phase, and a crash between those
   renames retries only the phase handoff.
2. Proceed to audit phase.
