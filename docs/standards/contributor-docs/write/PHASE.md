# Phase 2: Write

## State Machine

```
[scaffold] → [write_tier_1] → [write_tier_2] → [write_tier_3] → [write_tier_4] → [write_tier_5] → [write_tier_6] → completed
  team(S)      fp-loop(S)×N    fp-loop(S)×N    fp-loop(S)×N    fp-loop(S)×N    fp-loop(S)×N    fp-loop(S)×N

any [write_tier_N] --(gap reported)--> [gap_scaffold] --(replay)--> [write_tier_<replayTier>]
                                          team(S)
```

Scaffold is a single team agent. Each write tier uses the file-processor loop with parallel sonnet agents.

The march through the tiers is linear except for one edge: a writer that discovers a
missing dependency sends the phase back through `gap_scaffold` and into an earlier
tier. That edge is not an error path — it is the [Discovered-Gap
Transition](#discovered-gap-transition), and this file owns its mechanism.

## State File: `write-state.json`

<!-- canonical-block: write-state-schema -->

```json
{
  "step": "scaffold | gap_scaffold | write_tier_1 | write_tier_2 | write_tier_3 | write_tier_4 | write_tier_5 | write_tier_6 | completed",
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

This is the **canonical write-phase schema** — twelve top-level fields, and this file
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
| `approvedOverwrites` | array of paths | Paths the user explicitly approved overwriting, one entry per path     |
| `blockedCollisions`  | array of paths | Pre-existing paths seen but **not** approved — recorded, never written |
| `gapTransition`      | object or null | The in-flight discovered-gap transition; non-null blocks tier dispatch |
| `gapsResolved`       | array          | Append-only log of closed transitions, one entry per completed replay  |

Each `provenance` entry is:

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

`writeStatus` and `writtenHash` are the per-path provenance state. Together they
distinguish the three situations a replay has to tell apart, which no single flag can:

| `writeStatus` | `writtenHash` | Situation                   | What a writer may do                                  |
| ------------- | ------------- | --------------------------- | ----------------------------------------------------- |
| `pending`     | `null`        | Scaffolded, never written   | Write, if current bytes hash to `scaffoldHash`        |
| `written`     | `<sha256>`    | Body complete               | Nothing — the path is not tier input at all           |
| `pending`     | `<sha256>`    | Authorized replay of a body | Rewrite, if current bytes still hash to `writtenHash` |

**`writtenHash` is recorded whenever a writer completes**, in the same state update
that sets `writeStatus: "written"`. It is the sha256 of the exact bytes the writer
left on disk. On a replay the transition sets `writeStatus` back to `pending` and
**keeps** `writtenHash`, and that retained hash — not the pending status — is the
overwrite authority. `writeStatus: "pending"` on its own authorizes nothing: a path
whose bytes match neither `scaffoldHash` nor `writtenHash` changed under the workflow
(a half-written body from a crashed writer, or an outside edit) and is refused, exactly
as an unclassified collision is refused.

**Ownership is proven by hash, never inferred from shape.** A file is a run-owned
scaffold only if its current bytes hash to the `scaffoldHash` this run recorded when
it wrote them. A pre-existing draft that happens to be one line long is _not_ a
scaffold, and no heuristic about "looks like a summary" may be used to decide it is.
If the hash does not match, the path is treated as pre-existing and needs explicit
approval.

## Step Dispatch

| Step           | Agent         | Model  | Type    | File                                                  | Description                                |
| -------------- | ------------- | ------ | ------- | ----------------------------------------------------- | ------------------------------------------ |
| `scaffold`     | scaffolder    | sonnet | team    | `docs/standards/contributor-docs/write/scaffold.md`   | Create all files with frontmatter + TODOs  |
| `gap_scaffold` | scaffolder    | sonnet | team    | `docs/standards/contributor-docs/write/scaffold.md`   | Scaffold **only** `gapTransition.gapPaths` |
| `write_tier_1` | doc-writer ×N | sonnet | fp-loop | `docs/standards/contributor-docs/write/write-file.md` | Tier 1: foundations                        |
| `write_tier_2` | doc-writer ×N | sonnet | fp-loop | `docs/standards/contributor-docs/write/write-file.md` | Tier 2: concepts                           |
| `write_tier_3` | doc-writer ×N | sonnet | fp-loop | `docs/standards/contributor-docs/write/write-file.md` | Tier 3: algorithms                         |
| `write_tier_4` | doc-writer ×N | sonnet | fp-loop | `docs/standards/contributor-docs/write/write-file.md` | Tier 4: features                           |
| `write_tier_5` | doc-writer ×N | sonnet | fp-loop | `docs/standards/contributor-docs/write/write-file.md` | Tier 5: surfaces                           |
| `write_tier_6` | doc-writer ×N | sonnet | fp-loop | `docs/standards/contributor-docs/write/write-file.md` | Tier 6: indexes                            |

All write tiers use the same agent file (`write-file.md`), parameterized with the tier
number and file metadata. Both scaffold steps use the same agent file
(`scaffold.md`), parameterized with **the exact path set it is to classify and
create** — the whole plan on first entry, `gapTransition.gapPaths` on a gap scaffold.
The scaffolder never chooses its own input set.

## Step Dispatch Logic

On entry, spawn write state-agent to assess. **NEVER read step files directly** — spawn a teammate and tell it which step file to read. The file-processor loop is managed by the orchestrator using scripts.

Conditions are evaluated **in order**. The first row wins.

| #   | Condition               | Action                                                                                                                                                         |
| --- | ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `gapTransition != null` | **Finish the in-flight transition first** — resume it at its recorded `status` (see [Discovered-Gap Transition](#discovered-gap-transition)). No tier may run. |
| 2   | No `write-state.json`   | Create via state-agent with `step: "scaffold"`, spawn scaffolder                                                                                               |
| 3   | `step: "scaffold"`      | Spawn scaffolder (sonnet) — tell it to read `docs/standards/contributor-docs/write/scaffold.md`, input set = the whole plan                                    |
| 4   | `step: "gap_scaffold"`  | Spawn scaffolder (sonnet) — same file, input set = `gapTransition.gapPaths` and nothing else                                                                   |
| 5   | `step: "write_tier_N"`  | Run file-processor loop for tier N (see below)                                                                                                                 |
| 6   | `step: "completed"`     | Phase done — advance `task-state.currentPhase` to `"audit"` via state-agent                                                                                    |

Row 1 takes precedence over the step because a transition that is half-applied has a
`step` that is not yet true. Dispatching on it would run a tier against a queue the
transition has not finished extending.

## Scaffold Step

The scaffolder **classifies every planned path before writing anything**, then creates
only the files it is allowed to create, with frontmatter + a one-line summary and no
body content. This ensures cross-reference paths exist before writing begins, without
ever writing over documentation that was already there.

Order is load-bearing: classify → refuse/approve → write. Never write → discover.

After the scaffolder reports, via state-agent, in one update:

1. Record `writeQueue` = exactly the paths the scaffolder reports as writable —
   `new`, `run-owned-scaffold`, and `approved-overwrite` — and nothing else.
2. Record `provenance` for each, including the `scaffoldHash` of the bytes just
   written, `writeStatus: "pending"` and `writtenHash: null`.
3. Record `approvedOverwrites` and `blockedCollisions` verbatim from the report.
4. Set `scaffoldComplete: true`, `filesTotal` = `writeQueue.length`,
   `filesWritten` = 0, `step: "write_tier_1"`, `currentTier: 1`.

If `blockedCollisions` is non-empty, the phase **stops here** and reports them for a
decision. It does not advance to `write_tier_1` with an incomplete queue.

## File-Processor Loop (Per Tier)

For each `write_tier_N` step:

### 1. Initialize

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
  3. Wait for all agents in batch to complete
  4. For each completed file: bash docs/standards/contributor-docs/scripts/mark-done.sh .contributor-docs/write-tier-N/state.json <filename>
```

### 3. Tier Complete

When all files in the tier are processed, in one state-agent update:

- For each path the tier completed: set `provenance[path].writeStatus: "written"` and
  `provenance[path].writtenHash` to the sha256 of the bytes the writer left on disk
- Append N to `tiersCompleted`; set `currentTier: N+1`
- Recompute `filesWritten` as the number of `provenance` entries with
  `writeStatus == "written"` — **derive it, never increment it**
- If N < 6: update `step: "write_tier_{N+1}"`
- If N = 6: update `step: "completed"`

`filesWritten` is derived because an incremented counter and a replay disagree
immediately: a replay rewrites files that were already counted, and every gap would
inflate the total past `filesTotal`. Deriving from provenance means the counter cannot
drift from the thing it counts, and a crash between two updates cannot double-count.

If the tier produced gap reports, the tier boundary is also where they are collected —
see [Discovered-Gap Transition](#discovered-gap-transition). Open the transition
**before** advancing `step`; the transition itself sets the step it replays into.

## Context Provided to Each Doc-Writer

Each spawned doc-writer receives controlled context (see `docs/standards/contributor-docs/common/writing-order.md` for rationale):

| Input                                                | How to Provide                                                          |
| ---------------------------------------------------- | ----------------------------------------------------------------------- |
| The scaffolded file (frontmatter + one-line summary) | Read from disk, include in prompt                                       |
| Frontmatter of all cross-referenced files            | Read `crossLinks` paths from scaffolded files, extract frontmatter only |
| Relevant source code files                           | Read `sources` from doc-plan.yaml entry                                 |
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

**`gapTransition != null` blocks ordinary tier dispatch and is the recovery marker.**
Every run checks it before it looks at `step` (dispatch row 1). Its `status` says
exactly which durable effects have already landed, so a crashed transition is resumed
rather than restarted, and restarting one anyway is harmless because every status is
idempotent.

### The Mechanism

<!-- canonical-block: gap-transition-mechanism -->

| Status       | Advanced by  | Durable effect of reaching it                                                                                                                                                                                                                                                                                                        | Resume from a crash at this status                                                                                                                                                                             |
| ------------ | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| _(opening)_  | state-agent  | One atomic write creates `gapTransition` with `status: "enqueued"`, `reportedBy`, `gapPaths`, `replayTier`, `requeued`, `resetTiers`, `expectedScaffold: {}`, `cleanedTiers: []`, `openedAt`. Nothing else in the state file changes.                                                                                                | The record either exists or it does not. If it does not, the gap is lost and the audit phase rediscovers it; no half-open transition is possible.                                                              |
| `enqueued`   | orchestrator | `doc-plan.yaml` gains an entry for every `gapPaths` member (path, type, tier, description, sources, crossLinks). Then `status: "planned"`.                                                                                                                                                                                           | Re-add the entries. Adding an entry that is already present is a no-op, so a partially re-planned file converges.                                                                                              |
| `planned`    | scaffolder   | The scaffolder classifies **only** `gapPaths`, and reports the exact bytes it will write for each. The orchestrator records those bytes' sha256 into `expectedScaffold` and sets `status: "prepared"` — **before any file is created**.                                                                                              | Re-run the scoped classification. Nothing has been written yet, so nothing can be orphaned.                                                                                                                    |
| `prepared`   | scaffolder   | The scaffolder writes the gap files. Then, in one atomic state write: `writeQueue` extended with the gap paths; a `provenance` entry per path with `origin: "new"`, `scaffoldHash` = its `expectedScaffold` hash, `tier`, `writeStatus: "pending"`, `writtenHash: null`; `filesTotal` = `writeQueue.length`; `status: "scaffolded"`. | For each gap path: absent → write it; present and hashing to its `expectedScaffold` entry → it is ours, keep it; present and hashing to anything else → **stop**, record it in `blockedCollisions` and report. |
| `scaffolded` | state-agent  | One atomic write: `tiersCompleted` truncated to tiers `< replayTier`; `currentTier: replayTier`; `step: "write_tier_<replayTier>"`; `writeStatus: "pending"` restored for every `requeued` path (their `writtenHash` is **kept**); `filesWritten` recomputed; `status: "reset"`.                                                     | Re-apply. Every effect is an assignment to a known value, so re-applying an already-applied reset changes nothing.                                                                                             |
| `reset`      | orchestrator | For each tier in `resetTiers`, delete `.contributor-docs/write-tier-<N>/state.json` and everything under `.contributor-docs/write-tier-<N>/findings/`, appending N to `cleanedTiers` after each one. When `cleanedTiers` covers `resetTiers`, `status: "cleaned"`.                                                                   | Resume cleanup at the first tier not in `cleanedTiers`. Deleting an already-deleted artifact is a no-op.                                                                                                       |
| `cleaned`    | state-agent  | One atomic write: the record — plus `closedAt` — is appended to `gapsResolved`, and `gapTransition` is set to `null`. The transition is over and ordinary dispatch resumes at `step`.                                                                                                                                                | If `gapTransition` is still non-null the append may or may not have happened; the state-agent appends only if no `gapsResolved` entry shares this `openedAt`.                                                  |

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

**`requeued`** is the reporting path plus the transitive reverse-dependency closure of
the gap paths, restricted to work that is already queued:

```
G  = the set of gapPaths
R₀ = { reportedBy }
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

| Condition                                                         | Refusal              |
| ----------------------------------------------------------------- | -------------------- |
| Opening while `gapTransition != null`                             | `GAP_IN_FLIGHT`      |
| `replayTier > currentTier`                                        | `GAP_TIER_INVALID`   |
| A proposed gap path is already on `writeQueue`                    | `GAP_ALREADY_QUEUED` |
| A gap path appears in two or more prior `gapsResolved` entries    | `GAP_LOOP`           |
| A gap file on disk matches neither absence nor `expectedScaffold` | `GAP_COLLISION`      |

`GAP_LOOP` is the loop guard. A path that has been gap-scaffolded twice and is being
reported missing a third time is not a retry case — it is a planning failure, and
replaying it again would loop forever while every individual step reports success. Stop
and report instead.

### The Accepted Gap: A Writer That Dies Before Reporting

Step 0 of this transition — the writer noticing — has no durable form, and deliberately
so. Team agents never touch state files (`docs/standards/contributor-docs/workflow.md`),
and that rule is worth more than the case it costs us. A writer that discovers a gap and
then dies before reporting loses the discovery: its file is never marked done, so the
tier reprocesses it, and if that retry also fails to surface the gap, the missing link
survives the write phase.

This is accepted, and it is narrow, because the audit phase rediscovers it: an outbound
link that was left unwritten is an unresolved reference, and checking those is exactly
what the audit's fact-check arm does. The cost of the alternative — letting writers
persist state — is a race between parallel writers in the same tier on the same missing
path, which is the failure this transition was built to prevent.

## Consistency Checks

These are the mechanical forms of the contracts above. Run from the repository root;
each must produce the stated result.

1. **Field-set equality.** The canonical schema block here and its mirror in
   `docs/standards/contributor-docs/write/state-agent.md` must have identical sorted key
   lists. Both are selected by the `canonical-block: write-state-schema` marker rather
   than by fence position, because both files contain several fenced `json` blocks and a
   range extractor that concatenates two of them yields invalid JSON — a check that always
   errors is a check that asserts nothing.
2. **Provenance-shape equality.** Same comparison for the
   `canonical-block: write-provenance-record` blocks.
3. **No retired field survives.** The retired mis-ordering of `tiersCompleted` — the same
   two words the other way round — and a generic `errors` field appear nowhere in the
   contributor-docs tree. This check greps for the retired spelling, so this document
   deliberately does not write it out: a consistency check that matches the sentence
   describing it can never reach zero, and would have to be weakened to pass. Note the
   near-miss it guards: the retired name differs from the canonical one only by word
   order, so a careless global replace destroys the correct field.
4. **Legal-step equality** across this file's schema union, its state machine, its
   dispatch table, and the state-agent's validation list — all four name the same nine
   steps.
5. **No membership re-derivation from the plan.** Every surviving `doc-plan.yaml`
   reference under `write/` is a metadata lookup (`sources`, `crossLinks`, `description`,
   `type`, `tier` of a _planned_ entry) and never a source of queue or tier membership.
6. **The mechanism table appears exactly once** across the contributor-docs tree —
   selected by its `canonical-block: gap-transition-mechanism` marker.

## State Transitions

All state writes go through the **write state-agent** (sub-agent, haiku). Read `docs/standards/contributor-docs/write/state-agent.md` for the protocol.

**Bootstrap exceptions:** None.

## Phase Completion

When all tiers are complete:

1. Via state-agent: update `task-state.json`: `currentPhase: "audit"`
2. Proceed to audit phase
