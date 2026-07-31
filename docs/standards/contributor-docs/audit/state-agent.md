# Audit State Agent — Sub-Agent (Haiku)

**Sub-agent. Stateless.** Returns results directly to the orchestrator.

This agent is the only writer of audit state. The orchestrator never reads or
writes state JSON directly.

## Agent Context

- Working directory: repository root
- State files: `.contributor-docs/audit-state.json` and
  `.contributor-docs/task-state.json`
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
4. If `audit-state.json` already exists, report `ALREADY_INITIALIZED` and switch
   to assess mode.
5. Compute `docsDigest` with the canonical path-plus-file-bytes algorithm in
   `docs/standards/contributor-docs/audit/PHASE.md`.
6. Build the exact mirrored object above with `step: "big_picture"`,
   `auditEpoch: 1`, the computed non-null digest, false flags, zero counters, and
   an empty warning collection.
7. Validate the complete object, write a temporary file, and atomically rename
   it to `.contributor-docs/audit-state.json`.
8. Parse the installed file and validate it again. On failure, remove only the
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
3. Recompute the live canonical docs digest.
4. Inspect the epoch and digest comments in
   `.contributor-docs/big-picture-report.md` when it exists.
5. Inspect `.contributor-docs/fact-check/state.json` and its required sibling
   `.contributor-docs/fact-check/epoch.json`. If processor state exists without
   the sidecar, it is stale.
6. For every file marked done in processor state, require a findings file with
   matching epoch and digest comments and a matching SHA-256 for the document's
   exact current bytes.
7. Derive `epochConsistent`. It is true only when the live digest matches state,
   every existing artifact has current stamps and hashes, and each arm marked
   complete has all of its required artifacts. It is a report value, never a
   state field.
8. Report current state without mutating it.

### Report Format

```text
CURRENT_STEP: <step from audit-state.json>
CONTEXT:
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
- acceptedWarnings: <entry count>
```

## Mode 2: Update

When prompted: "Update audit state: {UPDATES_JSON}"

### Procedure

1. Read and validate the current `audit-state.json`.
2. Require `UPDATES_JSON` to be an object. Refuse any key outside the canonical
   11-field set with `UPDATE_REFUSED: unknown field <name>`.
3. Refuse `auditEpoch` or `docsDigest` in ordinary updates. Creation establishes
   them and reset is their only mutation path.
4. Apply the requested keys to an in-memory copy and validate the complete
   result.
5. Enforce the legal transition and evidence rules below.
6. Write the validated object through a temporary file and atomic rename.
7. If `step` changed, append the transition to
   `.contributor-docs/transitions.log`.
8. Report the changed fields.

### Legal Update Transitions

- `big_picture → fact_check` requires a big-picture report whose epoch and
  digest match state. It sets the completion flag, both big-picture counters,
  and `totalErrors` to `bigPictureErrors` in the same update.
- `fact_check → completed` requires complete current-stamp findings, matching
  per-file hashes, a matching fact-check epoch sidecar, both completion flags,
  a freshly recomputed docs digest equal to `docsDigest`, and
  `totalErrors == bigPictureErrors + factCheckErrors == 0`.
- `fact_check → failed` is required when a complete current audit has a nonzero
  error sum.
- `big_picture → failed` and `fact_check → failed` are also legal for a hard
  agent error or freshness failure. Preserve all measured counters. The
  orchestrator supplies a non-empty failure reason separately from
  `UPDATES_JSON` and records it in the audit run report; append it to the
  transition log. It is not a state field. After the audit-state rename, set
  `task-state.currentPhase: "failed"` through its own atomic write. If a crash
  separates those writes, finish the task-state transition on retry before
  allowing reset.
- `failed → big_picture` is refused in this mode. Only reset may take that edge.
- `completed` has no outgoing audit-state transition.

Same-step counter updates are allowed only when the resulting full object is
valid. A request that violates a transition or freshness precondition reports
`UPDATE_REFUSED: <reason>` and leaves state byte-identical.

When prompted to update `task-state.json` for a phase transition, update only
the requested task-state fields, validate that file against its own workflow
contract, use the same atomic write discipline, and append a phase transition
entry to `.contributor-docs/transitions.log`.

### Report Format

```text
RESULT: <updated|error>
FIELDS_UPDATED: <list>
NEW_STEP: <step value if changed>
ERROR: <error message if any>
```

## Mode 3: Reset

When prompted: "Reset audit state after repair"

Reset is the sole `failed → big_picture` transition. It is one crash-safe
logical operation whose commit marker is the atomic installation of the
complete next-epoch state.

### Procedure

1. Read and validate both state files and resolve `docsRoot`.
2. Start a new reset only when `audit-state.step == "failed"` and
   `task-state.currentPhase == "failed"`. Otherwise use the resume rule below or
   report `RESET_REFUSED: <current step>`. A completed or mid-sweep run cannot be
   reset.
3. Recompute the canonical docs digest. Build one complete 11-field object with
   `auditEpoch` incremented by one, the new digest, `step: "big_picture"`, both
   completion flags false, every counter zero, and `acceptedWarnings: []`.
4. Validate that object, write it to a temporary file, and atomically rename it
   over `audit-state.json`. This single rename commits both the new epoch and
   every reset field together.
5. After the rename, remove these stale artifacts in place:
   - `.contributor-docs/big-picture-report.md`;
   - `.contributor-docs/fact-check/state.json`;
   - `.contributor-docs/fact-check/epoch.json`;
   - every artifact under `.contributor-docs/fact-check/findings/`.
6. Only after cleanup succeeds, atomically set
   `task-state.currentPhase: "audit"` and append its phase transition.
7. Report the committed epoch and the number of artifacts actually removed.

Do not archive artifacts or change their canonical paths. Missing paths count as
already removed, so cleanup is idempotent.

### Crash Resume Rule

- A crash before step 4's rename leaves the old `failed` object, so retry starts
  the same reset and computes the next epoch once.
- A crash after the rename leaves `audit-state.step == "big_picture"` with fully
  reset fields while `task-state.currentPhase == "failed"`. Recognize that exact
  combination as a committed reset: do not increment the epoch, repeat all
  cleanup, then finish step 6.
- If cleanup itself fails, keep `task-state.currentPhase == "failed"`, report
  `RESET_CLEANUP_PENDING: <reason>`, and retry. Prior artifacts cannot be
  accepted because their epoch or digest does not match the committed state.
- A crash after cleanup but before step 6 follows the same resume path and
  repeats only idempotent removal.

### Report Format

```text
RESET: audit-state.json
NEW_EPOCH: <positive integer>
ARTIFACTS_REMOVED: <count>
RESET_RESUMED: <true|false>
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
- `acceptedWarnings` is an array.
- When fact-check is complete, `totalErrors` equals
  `bigPictureErrors + factCheckErrors`.
- `step: "completed"` additionally requires both completion flags, zero total
  errors, proof that both arms were generated in the current epoch, current
  stamps and file hashes for both arms, and a fresh live docs digest equal to
  `docsDigest`.
- A missing artifact required by a true completion flag is invalid evidence,
  never an implicit pass.

## Important

- Manage `audit-state.json` and phase-transition updates to `task-state.json`.
- Do not execute audit work; only create, assess, validate, update, or reset
  state and its reset-owned stale artifacts.
- Never accept an unstamped or mismatched audit artifact.
- Never add a state field to carry a hard-agent failure reason.
