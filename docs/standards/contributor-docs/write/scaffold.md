# Scaffold Files — Team Agent (Sonnet)

## Agent Context

- Working directory: repo root
- Doc plan: `.contributor-docs/doc-plan.yaml`
- Docs references:
  - `docs/standards/contributor-docs/frontmatter.md` — frontmatter schemas
  - `docs/standards/contributor-docs/structure.md` — folder structure

## Agent Report Format

```
RESULT: <success|error>
FILES_CREATED: <count>
DOCS_ROOT: <path>
ERROR: <error message if any>
```

**Do NOT update state files.** Report back to orchestrator only.

## Task

Read the doc plan and create every planned file with frontmatter and a one-line summary. No body content. This ensures all cross-reference paths exist before any writing begins.

## Steps

### 1. Read Inputs

Read `.contributor-docs/doc-plan.yaml` for the complete file manifest.
Read the frontmatter schemas doc for correct frontmatter per section type.
Read the structure doc for folder layout conventions.

### 2. Create Directory Structure

Create all necessary directories under the `docsRoot` specified in the plan:

```
<docsRoot>/
├── 00-overview.mdx
├── 01-architecture/
├── 02-modules.mdx
├── 03-development/
├── <module-name>/
│   ├── features/
│   ├── concepts/
│   ├── algorithms/
│   └── surfaces/
└── shared/
    ├── concepts/
    └── algorithms/
```

### 3. Scaffold Each File

For each file in the plan (across `modules`, `shared`, `topLevel`, `adrs`, `indexes`):

1. Build frontmatter from the plan entry + frontmatter schema for its type
2. Write the file with frontmatter + one-line summary (the `description` from the plan)
3. Do NOT write any body content beyond the one-line summary

Example scaffolded file:

```mdx
---
title: 'Token Refresh'
description: 'How auth tokens are refreshed without user interaction'
date: 2026-03-04
status: draft
type: flow
tags: [auth]
related: []
---

How auth tokens are refreshed without user interaction.
```

### 4. Verify Cross-References

After all files are created, verify that every path referenced in `crossLinks` across the plan resolves to an actual file on disk.

If any paths are missing, report them as warnings (they may indicate a plan error).

### 5. Report

Report the result with total file count and docs root path.

## Resumability and Collision Safety

A planned path that already exists is ambiguous: it may be this run's own
scaffold (resume) or **pre-existing documentation this run would destroy**. The
two are not the same and must never be collapsed into "already exists → success".

### Classify every planned path

For each path in the plan, record it in one of three buckets:

| Bucket         | Test                                                                         | Disposition                     |
| -------------- | ---------------------------------------------------------------------------- | ------------------------------- |
| `new`          | Path does not exist on disk                                                  | Scaffold it, queue it for write |
| `scaffolded`   | Exists, and its body is only the scaffold one-line summary (no real content) | Resume — queue it for write     |
| `pre-existing` | Exists **and** has body content beyond the one-line summary                  | **Collision — do not queue**    |

Report all three buckets. `pre-existing` is not a warning; it is a stop.

### Refuse on collision

If the `pre-existing` bucket is non-empty:

1. **Stop.** Do not scaffold over any of them, and do not queue them for write.
2. Show the user the exact collision set — every colliding path, one per line,
   with its current line count — so the decision is made against real files and
   not a summary.
3. Ask for explicit per-path approval. Approval is per path; a blanket "yes"
   must be given by the user, never inferred.
4. Only paths the user explicitly approves move to the write queue. Everything
   still unapproved is dropped from this run and reported as skipped.

This is the confirmation required by [workflow.md](../workflow.md) rule 3
("Never overwrite existing documentation files without user confirmation"). The
write phase queues **only** `new`, `scaffolded`, and explicitly approved paths —
it never re-derives the queue from the plan.

### Report Format

```
SCAFFOLDED: <count> new files
RESUMED: <count> existing scaffolds
COLLISIONS: <count>          # if > 0, this run is blocked pending approval
  <path> (<n> lines)
  ...
APPROVED_FOR_OVERWRITE: <paths the user explicitly approved, or none>
WRITE_QUEUE: <the exact paths the write phase may process>
```

## Important

- Do NOT update state files
- Do NOT write body content — only frontmatter + one-line summary
- Do NOT modify existing files that already have body content (beyond the one-line summary)
- Follow the frontmatter schemas exactly from the docs reference
