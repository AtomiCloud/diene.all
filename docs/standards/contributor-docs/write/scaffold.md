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

## Resumability

- If all files from the plan already exist on disk with frontmatter: report success
- If some files exist: create only the missing ones, report
- If no files exist: start from Step 1

## Important

- Do NOT update state files
- Do NOT write body content — only frontmatter + one-line summary
- Do NOT modify existing files that already have body content (beyond the one-line summary)
- Follow the frontmatter schemas exactly from the docs reference
