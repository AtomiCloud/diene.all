# Scaffold Files — Team Agent (Sonnet)

## Agent Context

- Working directory: repo root
- Operation: `{prepare|create}` (provided by orchestrator)
- Doc plan: `.contributor-docs/doc-plan.yaml`
- Docs references:
  - `docs/standards/contributor-docs/frontmatter.md` — frontmatter schemas
  - `docs/standards/contributor-docs/structure.md` — folder structure

## Agent Report Format

```text
RESULT: <success|error>
OPERATION: <prepare|create>
INPUT_SET: <whole-plan|gap-paths>
MANIFEST_JSON: <JSON array; required for prepare, exact shape below>
FILES_CREATED: <count; create only>
FILES_ADOPTED: <count; create only>
DOCS_ROOT: <path>
ERROR: <error message if any>
```

**Do NOT update state files.** Report back to orchestrator only.

## Task

`prepare` renders and classifies every handed path but writes nothing. `create` writes
or adopts only a manifest whose expected hashes are already durable. Splitting these
operations ensures a crash can never leave a scaffold whose ownership exists only in
a lost agent report.

## Steps

### 1. Read Inputs

**The orchestrator gives you the operation and exact input set. You never choose
either.** Initial `prepare` receives the complete plan; initial `create` receives the
prepared `writeQueue`. Gap operations receive exactly `gapTransition.gapPaths`.
Files outside that set are never classified or touched. See
`docs/standards/contributor-docs/write/PHASE.md` for each dispatch.

Read `.contributor-docs/doc-plan.yaml` for the metadata of the paths in your input set.
Read the frontmatter schemas doc for correct frontmatter per section type.
Read the structure doc for folder layout conventions.

In `create`, also read the already-persisted expected hashes from `provenance` for an
initial scaffold or `gapTransition.expectedScaffold` for a gap. Refuse an input path
without exactly one persisted expected hash.

### 2. Plan Directory Structure

Resolve all necessary directories under the `docsRoot` specified in the plan. In
`prepare`, only compute them. In `create`, make only the parents of handed paths:

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

### 3. Prepare: Classify and Render Without Writing

This step applies only to `prepare`. Do it for the **whole input set** before returning.
Do not create a directory or file. A sequential pass that writes as it classifies has
already destroyed a pre-existing file by the time it discovers the collision.

"Whole" means whole _input_, never "whole plan regardless of what you were handed".
Re-classifying the full plan on a gap scaffold would put every file this run has already
written back through the hash test, which they fail by construction — a written body does
not hash to its scaffold — so every one of them would be bucketed `pre-existing` and the
run would block on its own output.

Render each path's exact proposed bytes in memory. Return one JSON record per path:

```json
{
  "path": "docs/contributor/orders/features/checkout.mdx",
  "tier": 4,
  "disposition": "new | run-owned-scaffold | collision",
  "bytesBase64": "<base64 of the exact bytes create would write>",
  "expectedHash": "<sha256 of the decoded exact bytes>",
  "observedHash": "<sha256 of current bytes, or null when absent>",
  "lineCount": 83
}
```

`MANIFEST_JSON` must be a JSON array whose unique path set equals the handed input
exactly. Base64 makes frontmatter and newlines unambiguous; the state-agent decodes it
and independently recomputes `expectedHash`. `lineCount` is zero for an absent path.
For initial prepare, existing bytes without prior prepared ownership are collisions.
For gap prepare at status `planned`, every existing target is reported as a collision
even when it happens to equal the proposed bytes: the expected hash was not durable
before that observation. On a retry the report still describes filesystem truth; the
state-agent, not this agent, decides whether a still-matching unconsumed scaffold
approval resolves the observation.

### 4. Create: Prove the Prepared Manifest, Then Write or Adopt

This step applies only to `create`. Re-render every handed path, recompute its hash,
and require equality with the already-persisted expected hash **before writing any
path**. Then classify the current disk state of the **entire set** against durable
authority before writing any path:

| Context          | Create/adopt rule                                                                                    |
| ---------------- | ---------------------------------------------------------------------------------------------------- |
| Initial `new`    | absent → create; expected hash → adopt a crash-completed create                                      |
| Initial resumed  | expected hash → adopt                                                                                |
| Initial approved | exact unconsumed scaffold `approvedHash` → create; expected hash → adopt                             |
| Gap `prepared`   | absent → create; `expectedScaffold[path]` → adopt; exact unconsumed scaffold `approvedHash` → create |

A gap file matching `expectedScaffold[path]` at `prepared` is run-owned even though
its provenance has not been installed yet. That is the crash window the prepared hash
exists to close. At `planned`, the same unowned file was a collision; status is what
distinguishes coincidental pre-existence from a crash-completed prepared write.

Anything else is a collision: write nothing further and report the exact current
hash and line count. Never turn a create-time mismatch into an approval yourself.

For each authorized create:

1. Build frontmatter from the plan entry + frontmatter schema for its type
2. Write the file with frontmatter + one-line summary (the `description` from the plan)
3. Do NOT write any body content beyond the one-line summary
4. Re-hash the installed bytes and require the persisted expected hash

Paths adopted by expected hash are already correct and are left byte-identical. After
the whole set is created/adopted, freshly hash all of it and report both counts. The
state-agent, not this agent, finalizes provenance and consumes approvals.

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

### Ownership Depends on Both Hash and Durable Stage

| Durable stage                     | Hash that proves run ownership         |
| --------------------------------- | -------------------------------------- |
| Initial `scaffold_prepared`       | `provenance[path].scaffoldHash`        |
| Gap `prepared`                    | `gapTransition.expectedScaffold[path]` |
| Finalized scaffold or first write | `provenance[path].scaffoldHash`        |

The gap row is deliberately provenance-free: prepared expected hashes are committed
before create, while provenance is installed after create. Omitting that row turns a
crash-completed gap file into a false collision. Conversely, at gap `planned`, no
expected hash is durable yet, so an existing lookalike remains pre-existing.

**Never infer ownership from the body looking like a one-line summary.** A
pre-existing draft that contains frontmatter plus a single summary sentence is
byte-for-byte indistinguishable in _shape_ from a fresh scaffold, and treating shape
as proof is precisely how real documentation gets overwritten without confirmation.
Only a hash recorded **before the possible create** proves this run owns the bytes.
No applicable recorded hash means not ours, which means it needs approval.

### Refuse on collision

If any collision is non-empty:

1. **Stop.** Do not scaffold over any of them, and do not queue them for write.
2. Show the user the exact collision set — every colliding path, one per line,
   with its current line count — so the decision is made against real files and
   not a summary.
3. Ask for explicit per-path approval. Approval is per path; a blanket "yes"
   must be given by the user, never inferred.
4. Bind each approval to the freshly measured `observedHash`. An initial collision
   may instead be skipped; a discovered gap is required and remains blocked until
   approved.

This is the confirmation required by [workflow.md](../workflow.md) rule 3
("Never overwrite existing documentation files without user confirmation"). The
write phase queues **only** prepared `new`, hash-adopted run-owned, and explicitly
approved paths — it never re-derives the queue from the plan. The approval is consumed
by the scaffold create and gives no later writer standing authority.

### Report Format

For `prepare`, use the top-level `MANIFEST_JSON` report field exactly; summaries may
follow it but cannot replace it. For `create`, report the exact created/adopted path
lists and any collision with its current hash and line count. The orchestrator sends
the machine-readable result to the state-agent; neither component reconstructs the
manifest from prose.

## Important

- Do NOT update state files
- `prepare` performs no filesystem writes, including directory creation
- Do NOT write body content — only frontmatter + one-line summary
- Modify an existing file only under an exact, unconsumed scaffold approval
- Follow the frontmatter schemas exactly from the docs reference
