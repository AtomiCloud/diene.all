# Big Picture Audit — Team Agent (Opus)

## Agent Context

The orchestrator provides every run-bound value. Do not read state files to
discover them.

- Working directory: repository root
- Doc plan: `.contributor-docs/doc-plan.yaml`
- Docs root: the `task-state.json.docsRoot` value supplied by the orchestrator
- Authorized plan SHA-256: `{PLAN_SHA256}`, the exact
  `write-state.json.authorizedPlanHash` supplied after audit-state assessment
- Audit epoch: `{auditEpoch}`, a positive integer supplied by the orchestrator
- Docs digest: `{docsDigest}`, the current epoch's 64-character lowercase digest
- Docs references:
  - `docs/standards/contributor-docs/structure.md` — expected folder structure
  - `docs/standards/contributor-docs/checklist.md` — formatting rules

## Agent Report Format

```text
RESULT: <success|error>
AUDIT_EPOCH: <positive integer>
DOCS_DIGEST: <64 lowercase hex>
PLAN_SHA256: <64 lowercase hex>
ERRORS_FOUND: <count>
WARNINGS_FOUND: <count>
REPORT_FILE: .contributor-docs/big-picture-report.md
ERROR: <error message if any>
```

**Do not update state files.** Report back to the orchestrator only.

## Task

Perform a holistic audit of the generated documentation. Read all document files
at a high level (frontmatter, H2 headings, and the first paragraph per section).
Check structural coherence, coverage, cross-references, and terminology. Write a
stamped report for the supplied epoch, docs digest, and authorized plan identity.

## What to Check

### 1. Structural Coherence

- Do modules represent clean bounded contexts?
- Are there files that should be in a different module?
- Are there modules that should be merged or split?

### 2. Coverage

- Does every capability identified in `.contributor-docs/diff-summary.md` have
  corresponding documentation?
- Are there obvious gaps, such as a feature with no concept explaining its
  "why"?
- Do features with complex logic have corresponding algorithm docs?

### 3. Cross-Reference Integrity

- Do all `related`, `concepts`, `algorithms`, and `surfaces` paths in
  frontmatter resolve to real files?
- Do all inline links resolve to real files?
- Are there orphan files not linked from any index or other file?
- Are cross-links bidirectional where appropriate?

### 4. Terminology Consistency

- Is the same concept called the same name across all files?
- Do module overviews establish terminology that features and concepts follow?

### 5. Navigation Completeness

- Can every file be reached from `00-overview.mdx` through links and indexes?
- Does every module have an overview file?
- Do all section directories have an index file?

### 6. Index Completeness

- Does every file in each directory appear in its corresponding index?
- Are index groupings logical?

## Steps

### 0. Bind the Authorized Plan

Before inspecting a reusable report, reading documentation, or consuming any plan
metadata, hash the exact, complete bytes of `.contributor-docs/doc-plan.yaml` and
require equality with the supplied 64-character lowercase `{PLAN_SHA256}`. A missing
plan or mismatch is
`PLAN_DRIFT_BLOCKED: expected={PLAN_SHA256} actual=<hash-or-absent>`: do not reuse,
replace, or create the report and do not continue the audit.

The orchestrator obtained this value from a full audit-state assessment of the
immutable approved-plan and discovered-gap authority chain. This agent verifies that
identity but never authorizes a different live plan.

### 1. Check for a Current Report

If `.contributor-docs/big-picture-report.md` exists, read only enough to inspect
its machine-readable header and summary:

- Reuse it only when `audit-epoch`, `docs-digest`, and `plan-sha256` exactly match the
  supplied values and its summary is complete.
- A report with no stamp, a malformed stamp, or any mismatch is stale.
  Overwrite it by regenerating from step 2; never return its counts.

Immediately before returning a reusable report, freshly hash the exact live plan and
require equality with `{PLAN_SHA256}`. A mismatch is `PLAN_DRIFT_BLOCKED`, not a stale
report to count or overwrite.

A repair reset always increments the epoch, so a prior repair's report cannot
pass this check. Same-epoch reuse exists only for crash recovery.

### 2. Read All Files at a High Level

For each document file under the docs root:

1. Read the full frontmatter.
2. Read the H2 headings.
3. Read the first paragraph after each H2.

Do not read full file content. Focus on structure and metadata.

### 3. Read the Plan

Freshly hash `.contributor-docs/doc-plan.yaml` and require equality with
`{PLAN_SHA256}` immediately before parsing it. Then read that exact plan and
`.contributor-docs/diff-summary.md` for what was planned versus built.

### 4. Run Each Check

Evaluate each of the six check categories above. For every finding, record:

- **Category**: structural, coverage, cross-reference, terminology, navigation,
  or index
- **Severity**: error (must fix) or warning (non-blocking)
- **File(s)**: affected file paths
- **Description**: what is wrong and how to fix it

### 5. Write the Report

Write `.contributor-docs/big-picture-report.md` with the three comments immediately
after the title. Substitute the exact supplied values; do not copy the example values
literally. Render the complete report to a staged temp file in `.contributor-docs/`
before changing the canonical path, and hold no lock while rendering.

The install is one authority transaction from
[workflow.md](../workflow.md#authority-transaction): acquire the canonical lock,
freshly hash the exact live plan and require equality with `{PLAN_SHA256}`, recheck the
epoch and docs digest supplied to this run against freshly read `audit-state.json`, and
then freshly recheck those preimages and the prior report's exact bytes or proven
absence while holding the lock before an ordinary atomic rename over the report. On a
mismatch observed by that final check, remove the temp file, leave the prior report
byte-identical, and return `PLAN_DRIFT_BLOCKED`; on contention return `AUTHORITY_BUSY`
and install nothing. The compliant-writer scope of the final check is defined by
[Authority Transaction](../workflow.md#authority-transaction).

```markdown
# Big Picture Audit Report

<!-- audit-epoch: {auditEpoch} -->
<!-- docs-digest: {docsDigest} -->
<!-- plan-sha256: {PLAN_SHA256} -->

## Summary

- Audit epoch: {auditEpoch}
- Docs digest: {docsDigest}
- Plan SHA-256: {PLAN_SHA256}
- Errors: <count>
- Warnings: <count>
- Files audited: <count>

## Issues

### Errors

#### 1. <description>

- **Category**: <category>
- **File(s)**: <paths>
- **Fix**: <how to fix>

### Warnings

#### 1. <description>

- **Category**: <category>
- **File(s)**: <paths>
- **Fix**: <how to fix>

## Pass

- <checks that passed cleanly>
```

When a severity has no findings, state `None.` under that heading. Write the
whole report for this invocation; do not merge current results into an older
report.

Every warning is one contiguous item beginning with a level-four heading in the
exact form `#### N. <description>`. Its byte range ends immediately before the next
level-four item, the next level-three section, or end of file. Do not put two warnings
under one item heading. This boundary lets the state-agent derive an exact
`findingHash` and description for warning acceptance without trusting a caller summary.

### 6. Report

Freshly hash the exact live plan immediately before returning. Return the exact epoch,
digest, `PLAN_SHA256`, separate error and warning counts, and the canonical report
path only when it still matches. The orchestrator verifies all three on-disk comments
before it updates state. At acceptance the audit state-agent rehashes the live plan
and requires the report value, `authorizedPlanHash`, and fresh hash to be equal;
otherwise it returns `PLAN_DRIFT_BLOCKED` without changing state or artifacts.

## Artifact Binding

The report is evidence only for the exact `auditEpoch`, `docsDigest`, and
`PLAN_SHA256` stamped inside it. A missing or mismatched comment makes it stale
regardless of its counts, modification time, or filename. Stale reports are
regenerated and never accepted as a completed audit arm. Evidence from an
unauthorized plan cannot advance the audit.

## Important

- Do not update or read state files.
- Do not consume plan metadata or write/reuse a report unless the exact live plan
  hashes to `PLAN_SHA256`.
- Do not fix findings; only report them.
- Do not read full document content; use frontmatter, H2 headings, and first
  paragraphs.
- Do not read source code; that is the fact-checker's task.
