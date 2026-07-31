# Phase 3: Audit

## State Machine

```
[big_picture] → [fact_check] → completed   (0 errors)
    team(O)      fp-loop(S)×N ↘
                               failed      (1+ errors) → repair → [big_picture]
```

The big-picture auditor runs first (one opus agent, holistic view). Then fact-checkers run as a file-processor loop (one sonnet agent per doc file).

## State File: `audit-state.json`

```json
{
  "step": "big_picture | fact_check | completed | failed",
  "bigPictureComplete": false,
  "bigPictureErrors": 0,
  "bigPictureWarnings": 0,
  "factCheckComplete": false,
  "factCheckErrors": 0,
  "factCheckWarnings": 0,
  "totalErrors": 0,
  "acceptedWarnings": []
}
```

## Step Dispatch

| Step          | Agent               | Model  | Type    | File                                                   | Description                                           |
| ------------- | ------------------- | ------ | ------- | ------------------------------------------------------ | ----------------------------------------------------- |
| `big_picture` | big-picture-auditor | opus   | team    | `docs/standards/contributor-docs/audit/big-picture.md` | Holistic structure, coherence, and completeness audit |
| `fact_check`  | fact-checker ×N     | sonnet | fp-loop | `docs/standards/contributor-docs/audit/fact-check.md`  | Per-file accuracy audit against source code           |

## Step Dispatch Logic

On entry, spawn audit state-agent to assess. **NEVER read step files directly** — spawn a teammate and tell it which step file to read. The file-processor loop for fact-check is managed by the orchestrator using scripts.

| Condition             | Action                                                                                                    |
| --------------------- | --------------------------------------------------------------------------------------------------------- |
| No `audit-state.json` | Create via state-agent with `step: "big_picture"`, spawn big-picture-auditor                              |
| `step: "big_picture"` | Spawn big-picture-auditor (opus) — tell it to read `docs/standards/contributor-docs/audit/big-picture.md` |
| `step: "fact_check"`  | Run file-processor loop for fact-check (see below)                                                        |
| `step: "completed"`   | Phase done, audit was clean — advance `task-state.currentPhase` to `"completed"` via state-agent          |
| `step: "failed"`      | Errors outstanding — run the repair loop (see Phase Completion); never advance to `"completed"`           |

## Big Picture Step

Spawn a single opus team agent. After it reports back:

- Via state-agent: update `bigPictureComplete: true`, `bigPictureErrors: <error count from report>`, `bigPictureWarnings: <warning count>`, `step: "fact_check"`

Errors found here do **not** short-circuit the phase — fact-check still runs, so the
repair loop sees the whole picture at once. They are carried into `totalErrors` and
decide the final transition.

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
     - Tell it to read docs/standards/contributor-docs/audit/fact-check.md
     - Provide: the doc file path and its sources from doc-plan.yaml
  3. Wait for all agents in batch to complete
  4. For each completed file: bash docs/standards/contributor-docs/scripts/mark-done.sh .contributor-docs/fact-check/state.json <filename>
```

### 3. Fact Check Complete

When all files are processed:

- Aggregate findings from `.contributor-docs/fact-check/findings/`
- Count issues, split by severity into **errors** and **warnings**
- Via state-agent: update `factCheckComplete: true`, `factCheckErrors: <count>`, `factCheckWarnings: <count>`, `totalErrors: <big_picture + fact_check>`
- Set the step from the error count, never unconditionally:
  - `totalErrors == 0` → `step: "completed"`
  - `totalErrors > 0` → `step: "failed"`

## State Transitions

All state writes go through the **audit state-agent** (sub-agent, haiku). Read `docs/standards/contributor-docs/audit/state-agent.md` for the protocol.

**Bootstrap exceptions:** None.

## Phase Completion

When both audit steps are complete:

1. Compile a combined audit report from big-picture and fact-check findings
2. Classify every finding as an **error** (the docs state something untrue, or a
   required file/section is missing) or a **warning** (style, coverage
   suggestions, non-blocking nits)
3. Branch on the error count. **A nonzero error count may never reach
   `completed`:**

   | Result                     | `task-state.json` transition                                |
   | -------------------------- | ----------------------------------------------------------- |
   | 0 errors, 0 warnings       | `currentPhase: "completed"`                                 |
   | 0 errors, warnings present | `currentPhase: "completed"` — see the acceptance rule below |
   | 1 or more errors           | `currentPhase: "failed"` — never `completed`                |

4. Report the final summary with the error and warning counts stated separately

### Warning Acceptance

Warnings do not block completion, but they are not silently discarded: record
them in `audit-state.json` under `acceptedWarnings` with the audit report they
came from, so the completed state carries an explicit record of what was accepted.

### Repair Loop (`failed`)

`failed` is a working state, not a dead end. On re-invocation with
`currentPhase: "failed"`:

1. Present the outstanding errors from the audit report.
2. Fix them — by re-running the affected write-tier files, or by targeted edits
   to the offending documents.
3. Via state-agent: reset `audit-state.json` to `step: "big_picture"` and clear
   `errors`, then set `task-state.json` `currentPhase: "audit"`.
4. Re-audit from the top. Partial re-audits are not permitted: a fix in one file
   can falsify a big-picture finding elsewhere.

The loop repeats until an audit run reports zero errors. Only that clean run may
set `completed`.
