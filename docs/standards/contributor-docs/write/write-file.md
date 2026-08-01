# Write Doc File — Team Agent (Sonnet)

## Agent Context

- Working directory: repo root
- File to write: {filePath} (from orchestrator)
- File metadata: {type}, {tier}, {description}, {sources}, {crossLinks}, {tags} (from doc-plan.yaml)
- Authorized plan SHA-256: `{PLAN_SHA256}`, copied exactly from the assessed
  `write-state.json.authorizedPlanHash`
- Audit repair errors: {auditErrors, or none on the initial write}
- Planned output paths: {plannedPaths}, the complete normalized output-path set from
  the current plan at dispatch time
- Skill references (provided by orchestrator):
  - Body template for this section type (from `docs/standards/contributor-docs/common/templates.md`)
  - Formatting checklist (from `docs/standards/contributor-docs/checklist.md`)

## Agent Report Format

```
RESULT: <success|error>
FILE: <path written>
PLAN_SHA256: <64 lowercase hex>
LINES: <line count>
AUTHORIZED_FROM_HASH: <sha256 of the exact pre-write bytes, or none on error>
WRITTEN_HASH: <sha256 of the exact bytes written, or none on error>
GAPS: <none, or one per line in the format below>
  <proposed path> type=<concept|algorithm> tier=<N> reason=<why this file needs it>
ERROR: <error message if any>
```

`GAPS` is a **structured field, not prose**. The whole discovered-gap transition is
triggered by it, and a gap mentioned in a free-text paragraph is a gap the orchestrator
will miss. Report `GAPS: none` when there are none — an absent field is indistinguishable
from a forgotten one.

`AUTHORIZED_FROM_HASH` identifies the exact snapshot the writer replaced.
`WRITTEN_HASH` identifies the exact bytes it left on disk. Both are required lowercase
SHA-256 values on success. The state-agent validates the first against provenance or
one unconsumed approval, freshly validates the second against disk, and normalizes the
complete `GAPS` field. In one atomic `record-write` update it stores written status/hash
and a bound provenance `writerReport` containing the reporter, accepted plan/start/write
hashes, and exact gap tuples/reasons. Only then may the processor be marked done. An
absent, malformed, blank-reason, duplicate, or conflicting gap record refuses the whole
completion update; it is never dropped while the document is declared written.

**Do NOT update state files.** Report back to orchestrator only.

## Task

Write or replay the full body content for one queued documentation file. On its first
write the file contains frontmatter and a one-line scaffold summary; on replay it
contains a previously written body whose retained hash authorizes revision. Preserve
the frontmatter and produce complete body content in either case.

On an audit-repair replay, resolve every supplied current-stamp error. Compare each
stamped `missing-dependency` error's proposed path with `{plannedPaths}` at dispatch
time. If the path is absent, return the finding's exact proposed path, type, tier, and
reason under `GAPS` instead of explaining it inline or silently dropping it. If the path
is present — even when the retained finding is still typed `missing-dependency` —
downgrade it to a link-only repair: add the link and report no gap. The orchestrator
may prepare only the fixed gap-candidate sidecar after a true gap report; the write
state-agent alone authorizes and installs the exact live-plan successor before the
orchestrator dispatches its scoped scaffolding.

**Only files on the durable `writeQueue` in `write-state.json` reach this agent** —
`new`, hash-verified `run-owned-scaffold`, and paths the user explicitly approved for
overwrite. The orchestrator dispatches from that queue, never from `doc-plan.yaml`.

If the path you are handed is not in the queue, or its `provenance` entry is missing,
it is a collision that escaped classification: **stop, write nothing, and report it**.
Replacing it here would be the silent overwrite the workflow forbids.

The orchestrator verifies `provenance[path].writeStatus == "pending"` before dispatching
you. A path already marked `written` is not tier input at all; if you are handed one, the
dispatch is wrong and you stop the same way.

## Inputs Provided by Orchestrator

The orchestrator reads these and includes them in the agent prompt:

| Input                   | Description                                                                    |
| ----------------------- | ------------------------------------------------------------------------------ |
| Plan SHA-256            | Exact `authorizedPlanHash` reported by write-state assessment                  |
| Scaffolded file content | The existing file with frontmatter + one-line summary                          |
| Cross-ref frontmatter   | Frontmatter-only of all files listed in `crossLinks`                           |
| Source code files       | Content of files listed in `sources`                                           |
| Audit repair errors     | Current-epoch errors that named this path; absent on an initial write          |
| Planned output paths    | Complete normalized output-path set from the current plan at dispatch time     |
| Module overview         | The module's `overview.mdx` content (if tier > 1 and file belongs to a module) |
| Body template           | The H2 template for this section type                                          |
| Formatting checklist    | Quality rules to follow                                                        |

## Steps

### 0. Bind the Authorized Plan

Before consuming `{type}`, `{tier}`, `{description}`, `{sources}`, `{crossLinks}`,
`{tags}`, `{plannedPaths}`, or any content selected through those values, hash the
exact, complete bytes of `.contributor-docs/doc-plan.yaml`. Require
`{PLAN_SHA256}` to be 64-character lowercase hexadecimal and equal to that fresh
hash. A missing plan or mismatch is
`PLAN_DRIFT_BLOCKED: expected={PLAN_SHA256} actual=<hash-or-absent>`: do not modify
the document, do not report a gap, and do not use the supplied plan metadata.

The value is the current `authorizedPlanHash` only because the write state-agent
already validated the complete authority chain. This agent may verify that identity;
it may not derive a replacement authority from whatever bytes happen to be live.

### 1. Read the Scaffolded File

Read {filePath} from disk. Parse the frontmatter to understand the file's metadata, type, and cross-links.

### 2. Read Source Code

Freshly hash the exact live plan again and require equality with `{PLAN_SHA256}`
immediately before using `{sources}`, `{crossLinks}`, or `{plannedPaths}` and before
reading any source selected by them. Refuse with `PLAN_DRIFT_BLOCKED` on mismatch.

Read all files listed in `sources`. For large files (>500 lines), focus on:

- Exports / public API
- Key functions and their signatures
- Comments and docstrings
- Types and interfaces

### 3. Understand Context

From the provided inputs, understand:

- What this file's role is (from frontmatter `type` and `description`)
- What related files exist (from cross-ref frontmatter — titles and descriptions only)
- What terminology the module uses (from module overview)
- What the source code actually does
- Which stamped audit errors this replay must resolve, including any exact structured
  missing-dependency report it must return after comparing its target to
  `{plannedPaths}`

### 4. Write Body Content

Follow the body template for the section type. Replace the one-line summary with full content.

**Per section type:**

- **Feature**: Focus on observable behavior and why it exists. Defer "how" to algorithm links, "why" to concept links. Max 3 paragraphs in Overview.
- **Concept**: Explain the "why" clearly. Include comparison tables for `comparison` type. Include Mermaid diagrams for `flow` type.
- **Algorithm**: Focus on `## Why This Way` — rejected alternatives and roadblocks are more valuable than the approach itself. Use Mermaid for the approach diagram.
- **Surface**: One endpoint per file. Document all request/response schemas and error codes.
- **ADR**: List at least two options considered. Capture both positive and negative consequences.
- **Module overview**: Define the bounded context. Link to key features and concepts.
- **Index**: List every file in the directory with one-line descriptions. Group logically.
- **Top-level**: Select the exact template named by the plan type:
  [`top-level-overview`](../common/templates.md#project-overview-top-level-overview),
  [`top-level-architecture`](../common/templates.md#architecture-overview-top-level-architecture),
  [`top-level-modules`](../common/templates.md#module-map-top-level-modules),
  [`top-level-development`](../common/templates.md#development-guide-top-level-development),
  [`top-level-folder-structure`](../common/templates.md#folder-structure-top-level-folder-structure),
  or [`top-level-commands`](../common/templates.md#command-reference-top-level-commands).
  A generic top-level fallback is not valid.

### 5. Validate

Before writing:

- [ ] File does not exceed ~300 lines
- [ ] All code blocks have language specified
- [ ] All diagrams use Mermaid
- [ ] No inline explanation of content that should be in a linked concept/algorithm
- [ ] Cross-reference links use correct relative paths
- [ ] Frontmatter is preserved exactly (do not modify)

### 6. Write the File

Write the complete file (frontmatter + body) to {filePath}, replacing the scaffolded version.

Immediately before the authorized write, freshly hash the exact live plan and require
equality with `{PLAN_SHA256}`. Perform this check after validation and body rendering
but before any document bytes change. On mismatch, return `PLAN_DRIFT_BLOCKED` and
leave the document byte-identical.

Before writing, confirm {filePath}'s provenance still holds. Hash the current bytes and
check them against exactly these authorizations — the first that matches wins, and if
none matches, the file changed under you: **stop and report instead of writing**.

| Provenance state                                  | Authorized if current bytes hash to                              | Meaning                                |
| ------------------------------------------------- | ---------------------------------------------------------------- | -------------------------------------- |
| `writeStatus: "pending"`, `writtenHash: null`     | the recorded `scaffoldHash`                                      | First write over a finalized scaffold  |
| `writeStatus: "pending"`, `writtenHash: <sha256>` | the recorded `writtenHash`                                       | Replay while prior body is unchanged   |
| pending with renewed approval                     | one unconsumed `purpose: "writer-replay"` entry's `approvedHash` | Replace the exact newly approved bytes |

The middle row is the replay case, and it must be checked explicitly. On a replay the
file's bytes are the body you wrote last time, not the scaffold — so they will **not**
hash to `scaffoldHash`, and a guard that only knows about `scaffoldHash` refuses every
replayed file and jams the transition on its own correct output. A path whose
`writeStatus` is `pending` **and** whose provenance records a prior write is a
legitimate rewrite: proceed.

The approval row is one-use and exact-hash bound. `origin: "approved-overwrite"` is
history, not standing authority; it never permits "anything" and never outranks a
retained `writtenHash`. When bytes differ from both normal hashes, stop first. The
orchestrator may append a fresh approval only after showing that exact collision to
the user. After a successful approved write, `record-write` consumes that approval.

Note what is _not_ authorization: `writeStatus: "pending"` by itself. If `writtenHash`
is recorded and the bytes do not match it, something outside this workflow changed the
file — an outside edit, or a writer that crashed mid-write. Report it; the orchestrator
persists the exact mismatch through state-agent `record-writer-collision` and, if the
user approves, records a new hash-bound writer-replay approval. Never resolve it by
changing provenance first or by writing under an old path approval.

### 7. Report

Freshly hash the complete file after writing and report the result with file path,
accepted `PLAN_SHA256`, pre-write authorization hash, written hash, and line count.
Freshly hash the exact live plan once more immediately before returning and require it
to equal the reported `PLAN_SHA256`; otherwise return `PLAN_DRIFT_BLOCKED` instead of
a success result.

The accepting write state-agent freshly hashes the plan again during `record-write`
and requires equality among the report's `PLAN_SHA256`, `authorizedPlanHash`, and the
live hash. If they disagree it returns `PLAN_DRIFT_BLOCKED` and leaves write state and
processor artifacts byte-identical. A success report missing any of the three hashes
or the explicit structured `GAPS` field is an error and must not be marked done. A
successful empty gap report is durably represented as `writerReport.gaps: []`, not
`writerReport: null`.

## Important

- Do NOT update state files
- Do NOT create additional files — only write the one assigned file
- Do not consume plan metadata, sources, or cross-links unless the exact live plan
  hashes to `PLAN_SHA256`
- Do NOT modify the frontmatter — only add/replace body content
- Do NOT read full content of other doc files (only frontmatter was provided for cross-refs)
- If you discover a missing concept or algorithm that should exist, report it in the
  structured `GAPS` field and do NOT create it. Your obligation is exactly:
  1. Report the **proposed path**, the **section type**, the **tier that section type belongs to** (concepts → tier 2, algorithms → tier 3), and **why this feature needs it**.
  2. Finish the rest of the file normally.
  3. Leave the outbound link **unwritten**. Do not explain the missing concept inline, and do not link to a path that does not exist.
  4. Never create the file, and never touch state.

  The orchestrator re-plans, scoped-re-scaffolds and replays the owning tier. See
  `docs/standards/contributor-docs/common/writing-order.md` (Discovered Gaps) for why
  it works this way and
  `docs/standards/contributor-docs/write/PHASE.md` (Discovered-Gap Transition) for the
  mechanism. This is the only legal path.

- Keep the file under ~300 lines. If content exceeds this, split into subsections and note in your report which parts could become separate files
