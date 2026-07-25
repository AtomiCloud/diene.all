# Phase 3: Audit

## State Machine

```
[big_picture] → [fact_check] → completed
    team(O)      fp-loop(S)×N
```

The big-picture auditor runs first (one opus agent, holistic view). Then fact-checkers run as a file-processor loop (one sonnet agent per doc file).

## State File: `audit-state.json`

```json
{
  "step": "big_picture | fact_check | completed",
  "bigPictureComplete": false,
  "bigPictureIssues": 0,
  "factCheckComplete": false,
  "factCheckIssues": 0,
  "totalIssues": 0
}
```

## Step Dispatch

| Step          | Agent               | Model  | Type    | File                   | Description                                           |
| ------------- | ------------------- | ------ | ------- | ---------------------- | ----------------------------------------------------- |
| `big_picture` | big-picture-auditor | opus   | team    | `audit/big-picture.md` | Holistic structure, coherence, and completeness audit |
| `fact_check`  | fact-checker ×N     | sonnet | fp-loop | `audit/fact-check.md`  | Per-file accuracy audit against source code           |

## Step Dispatch Logic

On entry, spawn audit state-agent to assess. **NEVER read step files directly** — spawn a teammate and tell it which step file to read. The file-processor loop for fact-check is managed by the orchestrator using scripts.

| Condition             | Action                                                                          |
| --------------------- | ------------------------------------------------------------------------------- |
| No `audit-state.json` | Create via state-agent with `step: "big_picture"`, spawn big-picture-auditor    |
| `step: "big_picture"` | Spawn big-picture-auditor (opus) — tell it to read `audit/big-picture.md`       |
| `step: "fact_check"`  | Run file-processor loop for fact-check (see below)                              |
| `step: "completed"`   | Phase done — advance `task-state.currentPhase` to `"completed"` via state-agent |

## Big Picture Step

Spawn a single opus team agent. After it reports back:

- Via state-agent: update `bigPictureComplete: true`, `bigPictureIssues: <count from report>`, `step: "fact_check"`

## File-Processor Loop (Fact Check)

### 1. Initialize

Read `.contributor-docs/doc-plan.yaml`, extract ALL doc file paths (across modules, shared, topLevel, adrs — excluding indexes). Pipe into init-state.sh:

```bash
<all-doc-file-list> | bash docs/standards/contributor-docs/scripts/init-state.sh \
  .contributor-docs/fact-check/state.json \
  '<source-paths-json>' \
  <concurrent-agents> \
  '.contributor-docs/fact-check/findings'
```

If `.contributor-docs/fact-check/state.json` already exists with pending files, skip initialization (resumability).

### 2. Process Loop

```
while next-file.sh returns files:
  1. Get next batch: bash docs/standards/contributor-docs/scripts/next-file.sh .contributor-docs/fact-check/state.json --batch <N>
  2. For each file in batch, spawn a fact-checker team agent (sonnet):
     - Tell it to read audit/fact-check.md
     - Provide: the doc file path and its sources from doc-plan.yaml
  3. Wait for all agents in batch to complete
  4. For each completed file: bash docs/standards/contributor-docs/scripts/mark-done.sh .contributor-docs/fact-check/state.json <filename>
```

### 3. Fact Check Complete

When all files are processed:

- Aggregate findings from `.contributor-docs/fact-check/findings/`
- Count total issues
- Via state-agent: update `factCheckComplete: true`, `factCheckIssues: <count>`, `totalIssues: <big_picture + fact_check>`, `step: "completed"`

## State Transitions

All state writes go through the **audit state-agent** (sub-agent, haiku). Read `audit/state-agent.md` for the protocol.

**Bootstrap exceptions:** None.

## Phase Completion

When both audit steps are complete:

1. Compile a combined audit report from big-picture and fact-check findings
2. Present to user:
   - If issues found: display summary, offer to fix
   - If clean: report success
3. Via state-agent: update `task-state.json`: `currentPhase: "completed"`
4. Report final summary of generated docs with issue count
