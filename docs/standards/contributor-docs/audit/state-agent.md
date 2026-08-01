# Audit State Agent — Sub-Agent (Haiku)

**Sub-agent. Stateless.** Returns results directly to the orchestrator.

This agent is the only writer of audit state. The orchestrator never reads or
writes state JSON directly.

## Agent Context

- Working directory: repository root
- State files: `.contributor-docs/audit-state.json` and
  `.contributor-docs/task-state.json`; read-only source binding from
  `.contributor-docs/plan-state.json` and repair evidence from
  `.contributor-docs/write-state.json`
- Audit artifacts: `.contributor-docs/big-picture-report.md` and
  `.contributor-docs/fact-check/`
- Mode: `{create|assess|update|reset}`

## Canonical State Mirror

`docs/standards/contributor-docs/audit/PHASE.md` is canonical. The specifically
marked block below mirrors its 11 top-level fields exactly so drift can be
checked mechanically.

<!-- audit-state-schema -->

```json
{
  "step": "big_picture | fact_check | completed | failed",
  "auditEpoch": 1,
  "docsDigest": "39e77a6619ba41e414906e08eb0f1d62d3069469c2b7cd5f702058869f256fb9",
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

The array element schema is also mirrored from the canonical PHASE file:

<!-- canonical-block: accepted-warning-record -->

```json
{
  "artifactPath": ".contributor-docs/fact-check/findings/docs__guide.md",
  "artifactHash": "39e77a6619ba41e414906e08eb0f1d62d3069469c2b7cd5f702058869f256fb9",
  "auditEpoch": 1,
  "docsDigest": "39e77a6619ba41e414906e08eb0f1d62d3069469c2b7cd5f702058869f256fb9",
  "documentPath": "docs/contributor/guide.mdx",
  "documentHash": "39e77a6619ba41e414906e08eb0f1d62d3069469c2b7cd5f702058869f256fb9",
  "findingOrdinal": 1,
  "findingHash": "39e77a6619ba41e414906e08eb0f1d62d3069469c2b7cd5f702058869f256fb9",
  "severity": "warning",
  "description": "Clarify the retry example"
}
```

Every write uses a temporary file in `.contributor-docs/` followed by `mv`.
Validation happens before the rename. A refusal or validation failure leaves the
previous state byte-identical.

## Mode 0: Create

When prompted: "Create audit phase state"

This mode creates only `audit-state.json`. The plan state-agent owns
`task-state.json` and the clean start; see
[workflow.md](../workflow.md#clean-start-the-first-transition).

### Procedure

1. Create `.contributor-docs/` if necessary.
2. If `task-state.json` is absent, report `NOT_INITIALIZED`. If it does not
   parse, report `CREATE_FAILED: invalid task-state.json`.
3. Read `docsRoot` from `task-state.json`. Refuse with
   `CREATE_FAILED: docsRoot unresolvable` unless it is a non-empty string that
   resolves from the repository root to a directory.
4. Validate the canonical source snapshot from the diff summary. On mismatch report
   `SOURCE_DRIFT_BLOCKED` with exact evidence and create nothing.
5. If `audit-state.json` already exists, report `ALREADY_INITIALIZED` and switch
   to assess mode.
6. Compute `docsDigest` with the canonical path-plus-file-bytes algorithm in
   `docs/standards/contributor-docs/audit/PHASE.md`.
7. Build the exact mirrored object above with `step: "big_picture"`,
   `auditEpoch: 1`, the computed non-null digest, false flags, zero counters, and
   an empty warning collection.
8. Validate the complete object, write a temporary file, and atomically rename
   it to `.contributor-docs/audit-state.json`.
9. Parse the installed file and validate it again. On failure, remove only the
   audit-state file created by this mode and report `CREATE_FAILED: <reason>`.

### Report Format

```text
CREATED: audit-state.json
CURRENT_STEP: big_picture
AUDIT_EPOCH: 1
DOCS_DIGEST: <64 lowercase hex>
```

## Mode 1: Assess

When prompted: "Assess audit phase state"

### Procedure

1. Read and validate `audit-state.json`. Report `NOT_INITIALIZED` when absent
   and `INVALID_STATE: <reason>` when its exact schema is invalid.
2. Read `task-state.json` and resolve `docsRoot`.
3. Validate the canonical source snapshot, including the live diff-summary hash's
   equality to `plan-state.json.diffSummaryHash`. Derive `sourceSnapshotCurrent` and
   the complete binding/identity/digest mismatch or sorted outside dirty-path set. A
   false result blocks all ordinary and recovery dispatch without mutation.
4. Recompute the live canonical docs digest.
5. Inspect the epoch and digest comments in
   `.contributor-docs/big-picture-report.md` when it exists.
6. Inspect `.contributor-docs/fact-check/state.json` and its required sibling
   `.contributor-docs/fact-check/epoch.json`. If processor state exists without
   the sidecar, it is stale.
7. For every file marked done in processor state, require a findings file with
   matching epoch and digest comments and a matching SHA-256 for the document's
   exact current bytes.
8. Derive `epochConsistent`. It is true only when the live digest matches state,
   every existing artifact has current stamps and hashes, and each arm marked
   complete has all of its required artifacts. It is a report value, never a
   state field.
9. Derive `currentContentErrors` from error entries whose epoch/digest and, for
   fact-check, per-file hash are all current. Stored counters from a stale or partial
   artifact are not repair authority.
10. Read and validate `write-state.json` whenever audit or task state indicates a
    failed/repair cycle; report its step and `auditRepair` marker but never mutate it.
11. Only when audit step is `failed`, derive `repairPaths` by mapping every current
    content error to the exact queued, written path or paths whose body can resolve it.
    A `missing-dependency` selects its reporting document, not its proposed new path;
    its declared proposed-path addition is authorized later by the ordinary
    discovered-gap transition. Derive `repairOutOfScope` for every current error that
    has neither an existing queued rewrite path nor that declared gap route, including a
    skipped/non-queued reporting document or a required move, split, merge, removal, or
    unsupported queue-topology change. Never guess a repair path from prose. At any
    other audit step, report an empty `repairPaths` set and `repairOutOfScope: none`:
    partial audit findings never select a repair authority outcome.
12. Derive `writeDriftBlocked` when audit step is `failed`, task phase is `failed`, write
    step is `completed`, `currentContentErrors == 0`, and at least one queued written
    path is absent or its fresh live hash differs from retained `writtenHash`. Report
    the complete sorted normalized set of those paths. Otherwise report `none`; this
    outcome cannot replace the content-repair route when a current error exists.
13. Derive `failurePairingResumeRequired` when audit step is `failed`, task phase is
    still `audit`, write step is `completed`, and `auditRepair` is null or belongs to an
    older audit epoch. This is the crash window after the audit-state failure rename,
    not evidence that repair completed. A current `replaying` marker in this tuple is
    inconsistent state, not a failure-pairing signal.
14. Derive `resetResumeRequired` when audit step is `big_picture`, `auditEpoch >= 2`,
    and every reset field has its canonical fresh value, plus either:
    - task phase is still `failed` (the direct-reset task rename did not land); or
    - task phase is `audit` and at least one reset-owned artifact still carries a prior
      epoch/digest or prior format (post-repair reset cleanup did not finish).
15. Report current state without mutating it.

### Report Format

```text
CURRENT_STEP: <step from audit-state.json>
CONTEXT:
- taskPhase: <task-state currentPhase>
- writeStep: <write-state step>
- sourceSnapshotCurrent: <true|false>
- sourceSnapshotMismatch: <none | summary binding, identity/digest mismatch, or sorted outside dirty paths>
- auditEpoch: <positive integer>
- docsDigest: <64 lowercase hex>
- liveDocsDigest: <64 lowercase hex>
- epochConsistent: <true|false>
- bigPictureComplete: <true|false>
- bigPictureErrors: <count>
- bigPictureWarnings: <count>
- factCheckComplete: <true|false>
- factCheckErrors: <count>
- factCheckWarnings: <count>
- factCheckPending: <pending file count, if processor state exists>
- totalErrors: <count>
- currentContentErrors: <count of currently stamped error entries>
- repairPaths: <exact queued paths named by all repairable current errors>
- repairOutOfScope: <none | exact current errors that lack writer authority>
- writeDriftBlocked: <none | exact queued written paths whose live bytes drifted>
- auditRepair: <none | auditEpoch/status/paths from write state>
- failurePairingResumeRequired: <true|false>
- acceptedWarnings: <entry count>
- resetResumeRequired: <true|false>
```

## Mode 2: Named Update Operations

When prompted: `Update audit state: {OPERATION_JSON}`

The object must select exactly one operation below. No operation accepts a desired
step, flag, counter, digest, epoch, warning array, or task phase as a generic patch.
`complete-audit` alone may carry an optional `acceptedWarnings` claim, which is evidence
to compare with the independently derived set, never a value to install on trust.

### Universal Procedure

1. Read and completely validate the current audit and task state. Read write state when
   the selected recovery operation requires it.
2. Validate the canonical source snapshot. On mismatch report
   `SOURCE_DRIFT_BLOCKED` and leave all audit, task, and reset-owned artifacts
   byte-identical.
3. Require one of these exact envelopes:
   - `{"operation":"record-big-picture"}`;
   - `{"operation":"complete-audit"}` or that object plus only
     `acceptedWarnings: [...]`;
   - `{"operation":"fail-audit"}` or that object plus only a non-empty string
     `reason`;
   - `{"operation":"resume-failed-task-phase"}`;
   - `{"operation":"advance-task-phase-to-completed"}`.
4. Freshly read every artifact required by that operation and derive the complete
   candidate state or task transition. Never merge caller fields into state.
5. Enforce the source step, task phase, stamps, digests, document hashes, counters, and
   operation-specific rules below. Validate the complete candidate object before any
   write.
6. Write each changed state file through a temporary file and atomic rename. Append a
   step or phase transition only after its corresponding rename.
7. Report the selected operation and resulting fixed state. An unknown key, wrong
   envelope, wrong edge, or stale evidence is `UPDATE_REFUSED: <reason>` and leaves all
   files byte-identical except for the documented two-rename failure pairing.

### Legal Operations

| Operation                         | Legal source                                               | Required validation and effect                                                                                                                                                                                                                                                                                                                                                                                                                 |
| --------------------------------- | ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `record-big-picture`              | audit `big_picture`, task `audit`                          | Require the canonical report with current epoch/digest stamps. Independently enumerate its error and warning items and require its summary counters to match. Build the complete state with `bigPictureComplete: true`, the derived counters, `totalErrors` equal to derived big-picture errors, and `step: "fact_check"`.                                                                                                                     |
| `complete-audit`                  | audit `fact_check`, task `audit`                           | Require a complete current fact-check processor, exact current finding coverage, current epoch sidecar, matching document hashes, and unchanged live docs digest. Derive fact-check counters and the complete sorted accepted-warning set. Require the combined error sum to be zero. If the optional caller claim exists, require exact equality or refuse `WARNING_ACCEPTANCE_MISMATCH`; install only the derived set and enter `completed`. |
| `fail-audit`                      | audit `big_picture` or `fact_check`, task `audit`          | Without `reason`, require a complete current fact-check audit with a derived nonzero error sum; derive its final counters and enter `failed`. With `reason`, require a hard-agent or freshness failure, preserve every already measured field, and change only the audit step. In both forms, atomically rename audit state first, then task phase `audit → failed`; record the external reason outside audit state.                           |
| `resume-failed-task-phase`        | audit `failed`, task `audit`                               | Require write step `completed` and `auditRepair` null or bound to an older audit epoch. Change only task phase `audit → failed`. This is the sole recovery after `fail-audit` committed audit state but crashed before its paired task-state rename; it never resets evidence.                                                                                                                                                                 |
| `advance-task-phase-to-completed` | audit `completed`, task `audit` or exact retry `completed` | Revalidate every completed invariant, including current source, artifact stamps and hashes, live docs digest, counters, and exact accepted-warning derivation. Atomically change only task phase `audit → completed`. A retry that already observes that exact task phase is idempotent success.                                                                                                                                               |

`failed → big_picture` is refused in this mode; only reset may take that edge. Audit
`completed` has no outgoing audit-state edge: its only operation is the separately
fenced task-phase handoff above. A caller cannot manufacture same-step counters; file
processor state carries partial fact-check progress until a named terminal operation
derives the audit-state result.

### Report Format

```text
RESULT: <updated|error>
OPERATION: <record-big-picture|complete-audit|fail-audit|resume-failed-task-phase|advance-task-phase-to-completed>
FROM_STEP: <audit step>
NEW_STEP: <audit step>
TASK_PHASE: <task phase>
ERROR: <error message if any>
```

## Mode 3: Reset

When prompted: "Reset audit state after repair"

Reset is the sole `failed → big_picture` transition. It is one crash-safe
logical operation whose commit marker is the atomic installation of the
complete next-epoch state.

### Procedure

1. Read and validate audit, task, and write state files and resolve `docsRoot`.
2. Validate the canonical source snapshot. A mismatch is
   `SOURCE_DRIFT_BLOCKED` and leaves state and stale artifacts untouched.
3. Start a new reset only when `audit-state.step == "failed"`, write state is valid
   and `completed`, and exactly one fenced source holds:
   - **no-current-content-error retry:** derived `currentContentErrors == 0`, task
     phase is `failed`, and completed write provenance still matches every live file;
     or
   - **content repair complete:** `totalErrors > 0`, task phase is `audit`, and
     `write-state.auditRepair` has status `completed` with this exact failed audit's
     epoch and digest. Its non-empty path set is written, and every live marked file
     freshly matches its `writtenHash` after the repair replay.

   If the no-current-content-error tuple holds except for live-hash equality, report
   `WRITE_DRIFT_BLOCKED: <complete sorted normalized drifted paths>` and mutate nothing.
   This is a named terminal authority outcome: stale or externally changed written bytes
   cannot be reset away and are not collapsed into `INVALID_FAILED_STATE`.

   Otherwise use the resume rule below or report
   `RESET_REFUSED: <task phase>/<audit step>/<write step>`. In particular, a
   nonzero-error audit cannot reset directly from task phase `failed`, task phase
   `audit` without the exact completed marker is the failure-pairing crash rather than
   repair evidence, and an active repair tier cannot discard the failed evidence.

4. Recompute the canonical docs digest. Build one complete 11-field object with
   `auditEpoch` incremented by one, the new digest, `step: "big_picture"`, both
   completion flags false, every counter zero, and `acceptedWarnings: []`.
5. Validate that object, write it to a temporary file, and atomically rename it
   over `audit-state.json`. This single rename commits both the new epoch and
   every reset field together.
6. After the rename, remove these stale artifacts in place:
   - `.contributor-docs/big-picture-report.md`;
   - `.contributor-docs/fact-check/state.json`;
   - `.contributor-docs/fact-check/epoch.json`;
   - every artifact under `.contributor-docs/fact-check/findings/`.
7. Only after cleanup succeeds, atomically set task phase `failed → audit` for the
   no-current-content-error path and append its phase transition. For a completed content
   repair, require task phase already `audit` and leave it byte-identical.
8. Report the committed epoch and the number of artifacts actually removed.

Do not archive artifacts or change their canonical paths. Missing paths count as
already removed, so cleanup is idempotent.
The completed write marker remains as epoch-bound history; after the audit epoch
increments it is inert and cannot authorize a later reset.

### Crash Resume Rule

- A crash before step 5's rename leaves the old `failed` object, so retry starts
  the same reset and computes the next epoch once.
- A crash after the rename leaves `audit-state.step == "big_picture"` with fully
  reset fields while `task-state.currentPhase == "failed"`. Recognize that exact
  combination as a committed reset: do not increment the epoch, repeat all
  cleanup, then finish step 7.
- After a content-repair reset, task phase was already `audit`. If the committed fresh
  reset still has any prior-epoch or prior-format reset-owned artifact, recognize that
  stale artifact as the unfinished-cleanup marker: do not increment the epoch, repeat
  cleanup, and leave task phase `audit`. If cleanup had already finished, ordinary
  `big_picture` dispatch is safe and no reset resume is needed.
- If cleanup itself fails, leave `task-state.currentPhase` unchanged: `failed`
  for a direct reset or `audit` after completed content repair. Report
  `RESET_CLEANUP_PENDING: <reason>` and retry. Prior artifacts cannot be accepted
  because their epoch or digest does not match the committed state.
- A crash after cleanup but before step 7 follows the same resume path and
  repeats only idempotent removal.

### Report Format

```text
RESET: audit-state.json
NEW_EPOCH: <positive integer>
ARTIFACTS_REMOVED: <count>
RESET_RESUMED: <true|false>
RESET_SOURCE: <no-current-content-error|content-repair>
```

## Validation Rules

<!-- audit-legal-steps -->

The legal step set is exactly: `big_picture`, `fact_check`, `completed`,
and `failed`.

- The object has exactly the 11 canonical top-level keys; unknown or missing
  fields are refused rather than merged.
- `auditEpoch` is a JSON integer greater than or equal to 1.
- `docsDigest` is a non-null string matching `^[0-9a-f]{64}$`.
- `bigPictureComplete` and `factCheckComplete` are booleans.
- `bigPictureErrors`, `bigPictureWarnings`, `factCheckErrors`,
  `factCheckWarnings`, and `totalErrors` are non-negative JSON integers.
- `acceptedWarnings` is an array. Every element has exactly the ten mirrored fields;
  hashes and stamps have their canonical types, `findingOrdinal` is a positive
  integer, `severity` is exactly `warning`, document fields are both null only for
  the big-picture report, and artifact/ordinal pairs are unique. The array is empty
  before completion. At completed it exactly equals the independently derived set,
  sorted by artifact path under the C locale and then ordinal.
- When fact-check is complete, `totalErrors` equals
  `bigPictureErrors + factCheckErrors`.
- `step: "completed"` additionally requires both completion flags, zero total
  errors, proof that both arms were generated in the current epoch, current
  stamps and file hashes for both arms, and a fresh live docs digest equal to
  `docsDigest`. Its warning-record count equals the sum of both warning counters.
- A missing artifact required by a true completion flag is invalid evidence,
  never an implicit pass.

## Important

- Manage `audit-state.json` and phase-transition updates to `task-state.json`.
- Read `write-state.json` only to fence content-repair reset; write state-agent owns
  every write-state mutation.
- Do not execute audit work; only create, assess, validate, update, or reset
  state and its reset-owned stale artifacts.
- Never accept an unstamped or mismatched audit artifact.
- Never add a state field to carry a hard-agent failure reason.
