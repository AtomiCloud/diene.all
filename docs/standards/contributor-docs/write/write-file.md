# Write Doc File — Team Agent (Sonnet)

## Agent Context

- Working directory: repo root
- File to write: {filePath} (from orchestrator)
- File metadata: {type}, {tier}, {description}, {sources}, {crossLinks}, {tags} (from doc-plan.yaml)
- Skill references (provided by orchestrator):
  - Body template for this section type (from `docs/standards/contributor-docs/common/templates.md`)
  - Formatting checklist (from `docs/standards/contributor-docs/checklist.md`)

## Agent Report Format

```
RESULT: <success|error>
FILE: <path written>
LINES: <line count>
WRITTEN_HASH: <sha256 of the exact bytes written, or none on error>
GAPS: <none, or one per line in the format below>
  <proposed path> type=<concept|algorithm> tier=<N> reason=<why this file needs it>
ERROR: <error message if any>
```

`GAPS` is a **structured field, not prose**. The whole discovered-gap transition is
triggered by it, and a gap mentioned in a free-text paragraph is a gap the orchestrator
will miss. Report `GAPS: none` when there are none — an absent field is indistinguishable
from a forgotten one.

`WRITTEN_HASH` is what the orchestrator records as this path's `writtenHash` when it
marks the write complete. It is the sha256 of the exact bytes left on disk.

**Do NOT update state files.** Report back to orchestrator only.

## Task

Write the full body content for a single documentation file. The file already exists on disk with frontmatter and a one-line summary (from the scaffold step). Replace the one-line summary with complete body content.

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
| Scaffolded file content | The existing file with frontmatter + one-line summary                          |
| Cross-ref frontmatter   | Frontmatter-only of all files listed in `crossLinks`                           |
| Source code files       | Content of files listed in `sources`                                           |
| Module overview         | The module's `overview.mdx` content (if tier > 1 and file belongs to a module) |
| Body template           | The H2 template for this section type                                          |
| Formatting checklist    | Quality rules to follow                                                        |

## Steps

### 1. Read the Scaffolded File

Read {filePath} from disk. Parse the frontmatter to understand the file's metadata, type, and cross-links.

### 2. Read Source Code

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
- **Top-level**: Follow the specific template (overview, architecture, modules, development).

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

Before writing, confirm {filePath}'s provenance still holds. Hash the current bytes and
check them against exactly these authorizations — the first that matches wins, and if
none matches, the file changed under you: **stop and report instead of writing**.

| Provenance state                                  | Authorized if current bytes hash to | Meaning                           |
| ------------------------------------------------- | ----------------------------------- | --------------------------------- |
| `writeStatus: "pending"`, `writtenHash: null`     | the recorded `scaffoldHash`         | First write over your scaffold    |
| `writeStatus: "pending"`, `writtenHash: <sha256>` | the recorded `writtenHash`          | Authorized replay of a prior body |
| `origin: "approved-overwrite"`                    | anything                            | The user approved this path       |

The middle row is the replay case, and it must be checked explicitly. On a replay the
file's bytes are the body you wrote last time, not the scaffold — so they will **not**
hash to `scaffoldHash`, and a guard that only knows about `scaffoldHash` refuses every
replayed file and jams the transition on its own correct output. A path whose
`writeStatus` is `pending` **and** whose provenance records a prior write is a
legitimate rewrite: proceed.

Note what is _not_ authorization: `writeStatus: "pending"` by itself. If `writtenHash`
is recorded and the bytes do not match it, something outside this workflow changed the
file — an outside edit, or a writer that crashed mid-write. Report it; the orchestrator
resolves it by classifying the collision and, if the user approves, recording an
`approved-overwrite`. Never resolve it by writing.

### 7. Report

Report the result with file path and line count.

## Important

- Do NOT update state files
- Do NOT create additional files — only write the one assigned file
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
