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

Create every file in the input set the orchestrator handed you, with frontmatter and a one-line summary. No body content. This ensures all cross-reference paths exist before any writing begins.

## Steps

### 1. Read Inputs

**The orchestrator gives you your input set — the exact list of paths to classify and
create. You never choose it.** On first entry into the write phase that set is the
complete manifest in `.contributor-docs/doc-plan.yaml`. On a gap scaffold it is exactly
`gapTransition.gapPaths` and nothing else; files this run has already written are not in
it, are never classified, and keep their recorded scaffold hashes untouched. See
`docs/standards/contributor-docs/write/PHASE.md` for both dispatches.

Read `.contributor-docs/doc-plan.yaml` for the metadata of the paths in your input set.
Read the frontmatter schemas doc for correct frontmatter per section type.
Read the structure doc for folder layout conventions.

On a gap scaffold, report the exact bytes you will write for each path — and their
sha256 — **before** creating any file, so the orchestrator can record the expected
scaffold identity first. A crash between your write and that record would otherwise
leave a new file that nothing in the state file claims, and the next run would classify
this run's own scaffold as a pre-existing collision.

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

### 3. Classify Every Path in Your Input Set — Before Writing Anything

Do this for the **whole of your input set** first — the full plan on first entry, the
exact gap path list on a gap scaffold. Do not interleave classification with writing: a
sequential pass that writes as it goes will have already destroyed a pre-existing file
by the time it discovers the collision.

"Whole" means whole _input_, never "whole plan regardless of what you were handed".
Re-classifying the full plan on a gap scaffold would put every file this run has already
written back through the hash test, which they fail by construction — a written body does
not hash to its scaffold — so every one of them would be bucketed `pre-existing` and the
run would block on its own output.

See [Collision Safety](#resumability-and-collision-safety) below for the buckets and
the refusal protocol. Produce three lists: writable paths, blocked collisions, and
the approvals the user gave.

### 4. Scaffold Each Writable File

For each path classified `new` (or explicitly approved for overwrite):

1. Build frontmatter from the plan entry + frontmatter schema for its type
2. Write the file with frontmatter + one-line summary (the `description` from the plan)
3. Do NOT write any body content beyond the one-line summary
4. **Record the SHA-256 of the exact bytes just written** as that path's
   `scaffoldHash`, together with its tier

Paths classified `run-owned-scaffold` are already correct — leave them and carry their
existing hash forward. Paths in the blocked set are skipped entirely.

The hashes are what make ownership provable on the next run. Without them, "is this
my scaffold or someone's draft?" can only be guessed from the body's shape, and that
guess is what silently overwrites real documentation.

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

### 5. Verify Cross-References

After all files are created, verify that every path referenced in `crossLinks` by the entries in your input set resolves to an actual file on disk. Verifying is a read-only check — it never adds a path to the input set.

If any paths are missing, report them as warnings (they may indicate a plan error).

### 6. Report

Report the result with total file count and docs root path.

## Resumability and Collision Safety

A planned path that already exists is ambiguous: it may be this run's own
scaffold (resume) or **pre-existing documentation this run would destroy**. The
two are not the same and must never be collapsed into "already exists → success".

### Classify every planned path

For each path **in your input set**, record it in one of three buckets. The test is
**provenance, not shape**:

| Bucket               | Test                                                                                                     | Disposition                     |
| -------------------- | -------------------------------------------------------------------------------------------------------- | ------------------------------- |
| `new`                | Path does not exist on disk                                                                              | Scaffold it, queue it for write |
| `run-owned-scaffold` | Exists **and** its current bytes hash to the `scaffoldHash` recorded in `write-state.json` for that path | Resume — queue it for write     |
| `pre-existing`       | Exists and its hash does not match a recorded `scaffoldHash` (including: no hash recorded at all)        | **Collision — do not queue**    |

Report all three buckets. `pre-existing` is not a warning; it is a stop.

**Never infer ownership from the body looking like a one-line summary.** A
pre-existing draft that contains frontmatter plus a single summary sentence is
byte-for-byte indistinguishable in _shape_ from a fresh scaffold, and treating shape
as proof is precisely how real documentation gets overwritten without confirmation.
Only a recorded hash from this workflow's own state proves this run wrote the file.
No recorded hash means not ours, which means it needs approval.

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
write phase queues **only** `new`, `run-owned-scaffold`, and explicitly approved
paths — it never re-derives the queue from the plan.

### Report Format

The orchestrator persists this report into `write-state.json` (`writeQueue`,
`provenance`, `approvedOverwrites`, `blockedCollisions`) before any tier runs. The
report itself is transient; the state is what every later step reads.

```
INPUT_SET: <whole-plan | gap-paths>
SCAFFOLDED: <count> new files
RESUMED: <count> run-owned scaffolds (hash-verified)
COLLISIONS: <count>          # if > 0, this run is blocked pending approval
  <path> (<n> lines)
  ...
APPROVED_FOR_OVERWRITE: <paths the user explicitly approved, or none>
WRITE_QUEUE: <the exact paths the write phase may process>
PROVENANCE:
  <path> origin=<new|run-owned-scaffold|approved-overwrite> tier=<N> scaffoldHash=<sha256>
  ...
```

## Important

- Do NOT update state files
- Do NOT write body content — only frontmatter + one-line summary
- Do NOT modify existing files that already have body content (beyond the one-line summary)
- Follow the frontmatter schemas exactly from the docs reference
