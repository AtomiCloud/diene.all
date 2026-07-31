# Phase 2: Write

## State Machine

```
[scaffold] → [write_tier_1] → [write_tier_2] → [write_tier_3] → [write_tier_4] → [write_tier_5] → [write_tier_6] → completed
  team(S)      fp-loop(S)×N    fp-loop(S)×N    fp-loop(S)×N    fp-loop(S)×N    fp-loop(S)×N    fp-loop(S)×N
```

Scaffold is a single team agent. Each write tier uses the file-processor loop with parallel sonnet agents.

## State File: `write-state.json`

```json
{
  "step": "scaffold | write_tier_1 | write_tier_2 | write_tier_3 | write_tier_4 | write_tier_5 | write_tier_6 | completed",
  "scaffoldComplete": false,
  "currentTier": 0,
  "tiersCompleted": [],
  "filesWritten": 0,
  "filesTotal": 0,
  "writeQueue": [],
  "provenance": {},
  "approvedOverwrites": [],
  "blockedCollisions": []
}
```

This is the **canonical write-phase schema**, and this file is its single source of
truth. The write state-agent's create, assess and update modes must operate on
exactly these fields — no more, no fewer. Where the state-agent's own documentation
still describes different fields, this schema wins and the state-agent is the thing
that is wrong.

### The Durable Write Queue

| Field                | Type           | Meaning                                                                |
| -------------------- | -------------- | ---------------------------------------------------------------------- |
| `writeQueue`         | array of paths | The **only** paths any tier may process. Nothing else is ever written. |
| `provenance`         | path → record  | How each queued path was classified, and the evidence for it           |
| `approvedOverwrites` | array of paths | Paths the user explicitly approved overwriting, one entry per path     |
| `blockedCollisions`  | array of paths | Pre-existing paths seen but **not** approved — recorded, never written |

Each `provenance` entry is:

```json
{
  "docs/contributor/orders/features/checkout.mdx": {
    "origin": "new | run-owned-scaffold | approved-overwrite",
    "scaffoldHash": "<sha256 of the exact bytes this run scaffolded>",
    "scaffoldedAt": "<ISO-8601>",
    "tier": 4
  }
}
```

**Ownership is proven by hash, never inferred from shape.** A file is a run-owned
scaffold only if its current bytes hash to the `scaffoldHash` this run recorded when
it wrote them. A pre-existing draft that happens to be one line long is _not_ a
scaffold, and no heuristic about "looks like a summary" may be used to decide it is.
If the hash does not match, the path is treated as pre-existing and needs explicit
approval.

## Step Dispatch

| Step           | Agent         | Model  | Type    | File                                                  | Description                               |
| -------------- | ------------- | ------ | ------- | ----------------------------------------------------- | ----------------------------------------- |
| `scaffold`     | scaffolder    | sonnet | team    | `docs/standards/contributor-docs/write/scaffold.md`   | Create all files with frontmatter + TODOs |
| `write_tier_1` | doc-writer ×N | sonnet | fp-loop | `docs/standards/contributor-docs/write/write-file.md` | Tier 1: foundations                       |
| `write_tier_2` | doc-writer ×N | sonnet | fp-loop | `docs/standards/contributor-docs/write/write-file.md` | Tier 2: concepts                          |
| `write_tier_3` | doc-writer ×N | sonnet | fp-loop | `docs/standards/contributor-docs/write/write-file.md` | Tier 3: algorithms                        |
| `write_tier_4` | doc-writer ×N | sonnet | fp-loop | `docs/standards/contributor-docs/write/write-file.md` | Tier 4: features                          |
| `write_tier_5` | doc-writer ×N | sonnet | fp-loop | `docs/standards/contributor-docs/write/write-file.md` | Tier 5: surfaces                          |
| `write_tier_6` | doc-writer ×N | sonnet | fp-loop | `docs/standards/contributor-docs/write/write-file.md` | Tier 6: indexes                           |

All write tiers use the same agent file (`write-file.md`), parameterized with the tier number and file metadata.

## Step Dispatch Logic

On entry, spawn write state-agent to assess. **NEVER read step files directly** — spawn a teammate and tell it which step file to read. The file-processor loop is managed by the orchestrator using scripts.

| Condition              | Action                                                                                          |
| ---------------------- | ----------------------------------------------------------------------------------------------- |
| No `write-state.json`  | Create via state-agent with `step: "scaffold"`, spawn scaffolder                                |
| `step: "scaffold"`     | Spawn scaffolder (sonnet) — tell it to read `docs/standards/contributor-docs/write/scaffold.md` |
| `step: "write_tier_N"` | Run file-processor loop for tier N (see below)                                                  |
| `step: "completed"`    | Phase done — advance `task-state.currentPhase` to `"audit"` via state-agent                     |

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
   written.
3. Record `approvedOverwrites` and `blockedCollisions` verbatim from the report.
4. Set `scaffoldComplete: true`, `filesTotal` = `writeQueue.length`,
   `step: "write_tier_1"`, `currentTier: 1`.

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
```

Pipe that list — and only that list — into init-state.sh:

```bash
# Tier N paths come from the durable approved queue, not from doc-plan.yaml
<tier-N-queue-slice> | bash docs/standards/contributor-docs/scripts/init-state.sh \
  .contributor-docs/write-tier-N/state.json \
  '<source-paths-json>' \
  <concurrent-agents> \
  '.contributor-docs/write-tier-N/findings'
```

If `.contributor-docs/write-tier-N/state.json` already exists with pending files, skip initialization (resumability).

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

When all files in the tier are processed:

- Via state-agent: update `tiersCompleted` (append N), `filesWritten` (increment), `currentTier: N+1`
- If N < 6: update `step: "write_tier_{N+1}"`
- If N = 6: update `step: "completed"`

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

## State Transitions

All state writes go through the **write state-agent** (sub-agent, haiku). Read `docs/standards/contributor-docs/write/state-agent.md` for the protocol.

**Bootstrap exceptions:** None.

## Phase Completion

When all tiers are complete:

1. Via state-agent: update `task-state.json`: `currentPhase: "audit"`
2. Proceed to audit phase
