# Diff Analysis — Team Agent (Sonnet)

## Agent Context

- Working directory: repo root
- Base branch: {baseBranch} (from task-state.json)
- Documentation root: {docsRoot} (from task-state.json)
- Docs reference: Read `docs/standards/contributor-docs/classification.md` for classification heuristics

## Agent Report Format

```
RESULT: <success|error>
CHANGED_FILES: <count>
DIFF_SUMMARY: .contributor-docs/diff-summary.md
ERROR: <error message if any>
```

**Do NOT update state files.** Report back to orchestrator only.

## Task

Analyze all commits on the current branch relative to the base branch. Produce a structured summary of what was built, organized for documentation planning.

## Steps

### 1. Get the Diff

First apply the canonical source-snapshot procedure in
`docs/standards/contributor-docs/workflow.md#source-snapshot-invariant`. Refuse when
any dirty path is outside `.contributor-docs/` and `{docsRoot}`. Resolve and retain the
exact base, HEAD, and unique merge-base commit identities and compute the canonical
raw-tree diff digest before reading changed files.

Run `git diff <mergeBaseCommit>..<headCommit> --name-status` to get the list of
changed files. Run `git log <mergeBaseCommit>..<headCommit> --oneline` to get the
commit history. Do not re-resolve a moving ref between these commands; every read is
against the captured commit identities.

### 2. Read Changed Files

Read the content of all added and modified files. For large files (>500 lines), read the first 200 lines and the file's exports/public API.

### 3. Catalog Changes

For each meaningful change, record:

- **File path** and what it does
- **Category hint** (likely feature? concept? surface? internal?)
- **Complexity** (trivial, moderate, complex)
- **Dependencies** (what other changed files does it relate to?)

Use the classification heuristics from the docs reference. Remember: features are any noteworthy capability with interesting mechanics, not just user-visible behavior.

### 4. Write Summary

Write `.contributor-docs/diff-summary.md`:

````markdown
# Diff Summary

<!-- canonical-block: source-snapshot-record -->

```json
{
  "baseRef": "main",
  "baseCommit": "0123456789abcdef0123456789abcdef01234567",
  "headCommit": "89abcdef0123456789abcdef0123456789abcdef",
  "mergeBaseCommit": "0123456789abcdef0123456789abcdef01234567",
  "diffDigest": "39e77a6619ba41e414906e08eb0f1d62d3069469c2b7cd5f702058869f256fb9"
}
```

## Commits

- <commit list>

## Changed Files

- <file list with categories>

## Identified Capabilities

### <Capability Name>

- Files: <list>
- Category hint: feature/concept/algorithm/surface
- Complexity: trivial/moderate/complex
- Notes: <relevant context>

## Potential Modules

- <module name>: <files that belong to it>

## Cross-Cutting Concerns

- <items that span multiple modules>
````

Copy the marker and five-field JSON object exactly, substituting the captured values.
Commit IDs are lowercase object IDs in the repository's object format; `diffDigest`
is always lowercase SHA-256. This record is part of the diff-summary bytes and is
validated independently before `record-diff-analysis` binds the artifact hash.

### 5. Report

Report the result with file count and summary path.

## Resumability

- Check if `.contributor-docs/diff-summary.md` already exists
- If yes: parse and validate its source-snapshot record, rerun the canonical live
  check, and report success only when every identity and the diff digest still match
- If no: start from Step 1

## Important

- Do NOT update state files
- Do NOT classify changes into final doc types — that's the planner's job
- Do NOT create documentation files — only the diff summary
