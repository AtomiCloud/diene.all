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
  "filesTotal": 0
}
```

## Step Dispatch

| Step           | Agent         | Model  | Type    | File                  | Description                               |
| -------------- | ------------- | ------ | ------- | --------------------- | ----------------------------------------- |
| `scaffold`     | scaffolder    | sonnet | team    | `write/scaffold.md`   | Create all files with frontmatter + TODOs |
| `write_tier_1` | doc-writer ×N | sonnet | fp-loop | `write/write-file.md` | Tier 1: foundations                       |
| `write_tier_2` | doc-writer ×N | sonnet | fp-loop | `write/write-file.md` | Tier 2: concepts                          |
| `write_tier_3` | doc-writer ×N | sonnet | fp-loop | `write/write-file.md` | Tier 3: algorithms                        |
| `write_tier_4` | doc-writer ×N | sonnet | fp-loop | `write/write-file.md` | Tier 4: features                          |
| `write_tier_5` | doc-writer ×N | sonnet | fp-loop | `write/write-file.md` | Tier 5: surfaces                          |
| `write_tier_6` | doc-writer ×N | sonnet | fp-loop | `write/write-file.md` | Tier 6: indexes                           |

All write tiers use the same agent file (`write-file.md`), parameterized with the tier number and file metadata.

## Step Dispatch Logic

On entry, spawn write state-agent to assess. **NEVER read step files directly** — spawn a teammate and tell it which step file to read. The file-processor loop is managed by the orchestrator using scripts.

| Condition              | Action                                                                      |
| ---------------------- | --------------------------------------------------------------------------- |
| No `write-state.json`  | Create via state-agent with `step: "scaffold"`, spawn scaffolder            |
| `step: "scaffold"`     | Spawn scaffolder (sonnet) — tell it to read `write/scaffold.md`             |
| `step: "write_tier_N"` | Run file-processor loop for tier N (see below)                              |
| `step: "completed"`    | Phase done — advance `task-state.currentPhase` to `"audit"` via state-agent |

## Scaffold Step

The scaffolder creates every planned file with frontmatter + a one-line summary but no body content. This ensures all cross-reference paths exist before any writing begins.

After the scaffolder reports success, via state-agent: update `scaffoldComplete: true`, `step: "write_tier_1"`, `currentTier: 1`.

## File-Processor Loop (Per Tier)

For each `write_tier_N` step:

### 1. Initialize

Read `.contributor-docs/doc-plan.yaml`, extract all files with `tier: N`. Pipe the file paths into init-state.sh:

```bash
# Extract tier N file paths from doc-plan.yaml and initialize
<tier-N-file-list> | bash docs/standards/contributor-docs/scripts/init-state.sh \
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
     - Tell it to read write/write-file.md
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

Each spawned doc-writer receives controlled context (see `common/writing-order.md` for rationale):

| Input                                                | How to Provide                                                          |
| ---------------------------------------------------- | ----------------------------------------------------------------------- |
| The scaffolded file (frontmatter + one-line summary) | Read from disk, include in prompt                                       |
| Frontmatter of all cross-referenced files            | Read `crossLinks` paths from scaffolded files, extract frontmatter only |
| Relevant source code files                           | Read `sources` from doc-plan.yaml entry                                 |
| Module overview content (if tier > 1)                | Read module's `overview.mdx`                                            |
| Body template for the section type                   | From `common/templates.md`                                              |
| Formatting checklist                                 | From docs `checklist.md`                                                |

Writers do NOT receive the full content of other doc files.

## Parallel Within Tiers, Sequential Across Tiers

Within a single tier, all files are written in parallel (batched by concurrent agent count). Across tiers, the order is strict. See `common/writing-order.md` for the dependency rationale.

## State Transitions

All state writes go through the **write state-agent** (sub-agent, haiku). Read `write/state-agent.md` for the protocol.

**Bootstrap exceptions:** None.

## Phase Completion

When all tiers are complete:

1. Via state-agent: update `task-state.json`: `currentPhase: "audit"`
2. Proceed to audit phase
