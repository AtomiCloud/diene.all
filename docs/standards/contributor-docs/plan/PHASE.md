# Phase 1: Plan

## State Machine

```
[diff_analysis] → [classify] → [review] → completed
    team(S)         team(O)      inline
```

## State File: `plan-state.json`

<!-- canonical-block: plan-state-schema -->

```json
{
  "step": "diff_analysis | classify | review | completed",
  "diffSummaryReady": false,
  "diffSummaryHash": null,
  "planFile": null,
  "planHash": null,
  "reviewFeedback": null,
  "approved": false
}
```

This seven-field object is canonical. The plan state-agent mirrors it exactly and
refuses unknown fields. Hashes bind both review gates to the artifact bytes that were
actually assessed; a ready flag or path alone is not evidence that the file stayed
unchanged. The source snapshot is intentionally inside the hashed diff summary rather
than duplicated as state fields; its live identities are revalidated independently.
After the approved handoff, `planHash` remains the immutable user-approved baseline.
Any authorized discovered-gap successors are recorded as a hash chain in write state;
they do not rewrite plan state.

## Step Dispatch

| Step            | Agent         | Model  | Type    | File                                                    | Description                        |
| --------------- | ------------- | ------ | ------- | ------------------------------------------------------- | ---------------------------------- |
| `diff_analysis` | diff-analyzer | sonnet | team    | `docs/standards/contributor-docs/plan/diff-analysis.md` | Read git diff, catalog all changes |
| `classify`      | doc-planner   | opus   | team    | `docs/standards/contributor-docs/plan/classify.md`      | Classify changes, build doc plan   |
| `review`        | —             | —      | inline  | `docs/standards/contributor-docs/plan/review.md`        | Present plan to user for approval  |
| `completed`     | none          | —      | handoff | —                                                       | Advance task phase to write        |

## Step Dispatch Logic

On entry, spawn plan state-agent to assess. **NEVER read step files directly** — spawn a teammate and tell it which step file to read. Exception: `review` is inline.

| Condition                                        | Action                                                                                |
| ------------------------------------------------ | ------------------------------------------------------------------------------------- |
| No `plan-state.json`                             | Create via state-agent with `step: "diff_analysis"`, spawn diff-analyzer              |
| Later step with `sourceSnapshotCurrent: false`   | Invoke `invalidate-diff-summary`; do not dispatch against changed source              |
| Later step with `diffSummaryHashCurrent: false`  | Invoke `invalidate-diff-summary`; do not dispatch the stale step                      |
| `step: "diff_analysis"`                          | Spawn diff-analyzer, then invoke `record-diff-analysis` on its complete artifact      |
| `step: "classify"`                               | Spawn doc-planner, then invoke `record-classification` on its complete validated plan |
| `step: "review"`                                 | If plan hash is current, run inline review; otherwise invoke `invalidate-plan`        |
| `step: "completed"` and `planHashCurrent: true`  | Advance `task-state.currentPhase` to `"write"` via state-agent                        |
| `step: "completed"` and `planHashCurrent: false` | Invoke `invalidate-plan`; do not attempt the task-phase handoff                       |

The source snapshot includes the live diff-summary-to-`diffSummaryHash` binding after
`record-diff-analysis`. The source-snapshot and diff-summary mismatch rows are evaluated before every named
later step (`classify`, `review`, or `completed`) and are the only dispatch until stale
source and artifact identities are cleared.
A plan-hash mismatch similarly preempts `review` and `completed` through
`invalidate-plan`. It does not block `classify`: after a rejection the classifier is
expected to replace the retained rejected-plan bytes, and `record-classification`
validates and binds that complete new candidate.

## State Transitions

All state writes go through the **plan state-agent** (sub-agent, haiku). Read `docs/standards/contributor-docs/plan/state-agent.md` for the protocol.

**Bootstrap exceptions:** None.

Generic field patches are forbidden. The state-agent accepts only these named edges:

| Operation                     | From                                 | To              | Evidence and effect                                                                                                                                         |
| ----------------------------- | ------------------------------------ | --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `record-diff-analysis`        | `diff_analysis`                      | `classify`      | Require the complete diff summary and a current canonical source snapshot, record its fresh SHA-256, and set `diffSummaryReady: true`                       |
| `invalidate-diff-summary`     | `classify`, `review`, or `completed` | `diff_analysis` | Require a proven summary-hash or source-snapshot mismatch; clear summary readiness/hash, plan identity, feedback, and approval                              |
| `record-classification`       | `classify`                           | `review`        | Require current source and the same diff-summary hash, exact plan/task `docsRoot` equality, and a fully validated `doc-plan.yaml`; record its path/hash     |
| `reject-plan`                 | `review`                             | `classify`      | Require explicit non-empty user feedback bound to the unchanged plan hash; preserve it for the next classifier                                              |
| `invalidate-plan`             | `review` or `completed`              | `classify`      | Require a current diff summary and proven live/recorded plan-hash mismatch; clear stale plan identity and approval, then install fixed classifier feedback  |
| `approve-plan`                | `review`                             | `completed`     | Require current source plus explicit user approval of the unchanged plan hash and atomically set `approved: true`                                           |
| `advance-task-phase-to-write` | `completed`                          | `completed`     | Require current source and all completed invariants, then update only task phase and its matching plan path from `plan` to `write` through an atomic rename |

No operation accepts a caller-supplied target step, approval flag, counter, path, or
task phase as a generic patch. A wrong source step, stale required hash, absent artifact,
invalid plan, or unrecognized operation leaves both state files byte-identical.

Every edge above, the clean-start bootstrap, and the diff-summary and classifier
artifact installs run as one authority transaction each — see
[workflow.md](../workflow.md#authority-transaction). Inputs are reread and fully
revalidated after the lock is acquired, the rename is conditional on those exact
preimages, and the transition log is appended before the lock is released.
Contention returns `AUTHORITY_BUSY` and mutates nothing, so the orchestrator
reassesses and retries rather than queueing behind a held lock.

## Review Loop

If the user rejects the plan:

1. State-agent `reject-plan` captures feedback in `reviewFeedback`, after proving the
   reviewed plan hash is still current.
2. The same atomic operation sets `step` back to `"classify"`.
3. Re-spawn doc-planner with the feedback

Loop continues until approved.

If plan bytes change outside the classifier while state is `review` or during the
post-approval `completed` handoff window, do not present or advance them. State-agent
`invalidate-plan` proves the mismatch, clears the stale identity and any approval,
installs fixed non-user feedback describing the invalidation, and returns to `classify`.
If the diff summary or its bound source snapshot moves instead,
`invalidate-diff-summary` clears both artifact identities and returns to
`diff_analysis`.

## Phase Completion

When approved:

1. State-agent `approve-plan` binds the explicit decision to the current `planHash` and
   reaches plan step `completed`.
2. State-agent `advance-task-phase-to-write` revalidates the source snapshot and both
   artifact hashes, then updates only `task-state.json.currentPhase: "write"` and its matching `planFile`.
   A summary mismatch first invokes `invalidate-diff-summary`; a plan mismatch first
   invokes `invalidate-plan`.
3. Treat the completed plan state, including `planHash`, as read-only input from this
   point onward. The write state-agent initializes `authorizedPlanHash` from it, and
   only the discovered-gap authority chain may advance the live plan identity.
4. Proceed to write phase.
