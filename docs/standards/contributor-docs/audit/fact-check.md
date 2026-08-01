# Fact Check — Team Agent (Sonnet)

## Agent Context

The orchestrator supplies all run-bound values:

- Working directory: repository root
- Doc file to check: `{filePath}`
- Documentation root: `{docsRoot}` from `task-state.json`
- Source files: `{sources}` from `doc-plan.yaml`
- Planned metadata: `{type}`, `{tier}`, and `{crossLinks}` from the same exact plan
  entry
- Planned output paths: `{plannedPaths}`, the complete normalized output-path set from
  that exact plan
- Audit epoch: `{auditEpoch}`, a positive integer
- Docs digest: `{docsDigest}`, a 64-character lowercase digest
- Document file SHA-256: `{docFileHash}`, the hash of the exact assigned bytes
- Output directory: `.contributor-docs/fact-check/findings/`
- Docs reference: `docs/standards/contributor-docs/checklist.md`

## Agent Report Format

```text
RESULT: <success|error>
AUDIT_EPOCH: <positive integer>
DOCS_DIGEST: <64 lowercase hex>
DOC_FILE_SHA256: <64 lowercase hex>
FILE: <document file checked>
ERRORS_FOUND: <count>
WARNINGS_FOUND: <count>
FINDINGS_FILE: <path to findings file>
ERROR: <error message if any>
```

**Do not update state files.** Report back to the orchestrator only.

## Task

Check one documentation file against its source code for accuracy,
completeness, staleness, and formatting compliance. Write a finding bound to the
current audit epoch, complete docs digest, and exact bytes audited.

## Steps

### 1. Read and Bind the Document

Read `{filePath}` completely, including frontmatter and body. Compute SHA-256
from the exact bytes read and compare it with `{docFileHash}`.

If the values differ, or if the file changes before the finding is written,
return `RESULT: error` without writing a finding. The orchestrator treats this
as stale epoch evidence and makes the legal transition to `failed` rather than
accepting a result for moving bytes.

### 2. Read the Source Code

Read every file in `{sources}`. For files longer than 500 lines, focus on:

- exports and public API;
- key functions, signatures, and inline comments;
- types and interfaces;
- error-handling patterns.

### 3. Check Accuracy

Compare documentation claims with source code:

- **Function or method names**: do documented names exist?
- **Parameter types**: do documented types match?
- **Behavior descriptions**: do they describe what the code does?
- **Code examples**: are snippets correct and runnable?
- **Configuration values**: are defaults, environment variables, and keys
  accurate?
- **Error handling**: are documented error cases real?

### 4. Check Completeness

Compare source capabilities with documentation coverage:

- **Missing behaviors**: is significant behavior undocumented?
- **Missing edge cases**: are important error paths skipped?
- **Missing configuration**: are configurable options omitted?
- **Missing dependencies**: does a reusable concept or algorithm required to explain
  a significant source behavior have neither a planned `crossLinks` target nor a valid
  outbound link? This is an error even though there is no broken link on disk. If its
  target is already in `{plannedPaths}`, record an ordinary `completeness` error to add
  the missing cross-link; do not propose a gap. Only when no planned path supplies the
  dependency, record `missing-dependency` with a normalized repository-root-relative
  proposed path contained by `{docsRoot}`, `concept|algorithm` type, tier `2|3`, and a
  non-empty reason. Do not accept explaining that reusable material inline.

This source-to-plan comparison is the durable backstop for a writer that noticed a
gap but died before returning its report. Link validation alone cannot rediscover an
omitted link, so every fact-check must perform this check explicitly.

### 5. Check Staleness

Look for documentation of things that no longer exist:

- **Removed functionality**: does the file describe removed APIs?
- **Renamed items**: does it use an obsolete name?
- **Changed behavior**: does its description differ from current code?

### 6. Check Formatting

Run through the formatting checklist:

- [ ] All code blocks have a language.
- [ ] All diagrams use Mermaid.
- [ ] Headers follow the expected template for this section type.
- [ ] The file does not exceed approximately 300 lines.
- [ ] Content that belongs in a linked file is not explained inline.
- [ ] Cross-reference links use correct relative paths.

### 7. Write Findings

Derive the findings filename by replacing `/` with `__` and changing the final
`.mdx` or `.md` suffix to `.md`. Before writing, hash `{filePath}` again and
require the result to equal `{docFileHash}`.

Write `.contributor-docs/fact-check/findings/<findings-filename>` with all three
comments immediately after the title:

```markdown
# Fact Check: {filePath}

<!-- audit-epoch: {auditEpoch} -->
<!-- docs-digest: {docsDigest} -->
<!-- doc-file-sha256: {docFileHash} -->

## Summary

- Audit epoch: {auditEpoch}
- Docs digest: {docsDigest}
- Document file SHA-256: {docFileHash}
- Accuracy errors: <count>
- Completeness errors: <count>
- Staleness errors: <count>
- Formatting errors: <count>
- Warnings: <count>
- Total errors: <count>

## Issues

### 1. <title>

- **Type**: accuracy | completeness | missing-dependency | staleness | formatting
- **Severity**: error | warning
- **Location**: <line number or section in document>
- **Source**: <source file and line, if applicable>
- **Description**: <what is wrong>
- **Fix**: <how to fix>
- **Proposed dependency**: <normalized path under docsRoot; required for missing-dependency>
- **Dependency type/tier**: <concept|algorithm> / <2|3; required for missing-dependency>
- **Reason**: <why this document needs it; required for missing-dependency>

## Clean

- <checks that passed>
```

If no findings exist, write `Total errors: 0`, `Warnings: 0`, and list all
passed checks under `Clean`. Every processed file gets a finding, including a
clean file.

Every issue is one contiguous item beginning with a level-three heading in the exact
form `### N. <description>`, and it carries exactly one `Severity` line. Its byte range
ends immediately before the next level-three item, the next level-two section, or end
of file. Do not group two warnings under one heading. For warning items, these exact
bytes and the heading description are the source of the accepted-warning
`findingHash` and `description`; caller-provided warning summaries are not evidence.

Write a complete replacement finding for this invocation. Never merge with or
append to an earlier finding.

### 8. Report

Return the exact epoch, docs digest, document hash, separate error and warning
counts, and findings path.

## Epoch Binding

A finding is evidence only when all of these values match at acceptance time:

- its `audit-epoch` comment equals `audit-state.json.auditEpoch`;
- its `docs-digest` comment equals `audit-state.json.docsDigest`;
- its `doc-file-sha256` comment equals a fresh SHA-256 of its assigned file;
- the fact-check `epoch.json` sidecar matches the same epoch and digest.

A missing or mismatched stamp makes the finding stale. The orchestrator
regenerates it and does not mark the file done. This agent never reads a prior
finding to short-circuit its work; there is no per-file artifact resumability.
Processor-level resumability comes only from current-stamp processor state plus
already verified findings.

## Important

- Do not update state files.
- Do not fix findings; only report them.
- Do not read other documentation files; read only the assigned document and
  its source code.
- Use only the orchestrator-supplied plan metadata for dependency membership; never
  discover additional queue members by scanning other documentation files.
- Do not modify the document or source files.
- Always write a finding after a successful current-byte audit, even when clean.
