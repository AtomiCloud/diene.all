# Write Doc File — Team Agent (Sonnet)

## Agent Context

- Working directory: repo root
- File to write: {filePath} (from orchestrator)
- File metadata: {type}, {tier}, {description}, {sources}, {crossLinks}, {tags} (from doc-plan.yaml)
- Skill references (provided by orchestrator):
  - Body template for this section type (from `common/templates.md`)
  - Formatting checklist (from `docs/standards/contributor-docs/checklist.md`)

## Agent Report Format

```
RESULT: <success|error>
FILE: <path written>
LINES: <line count>
ERROR: <error message if any>
```

**Do NOT update state files.** Report back to orchestrator only.

## Task

Write the full body content for a single documentation file. The file already exists on disk with frontmatter and a one-line summary (from the scaffold step). Replace the one-line summary with complete body content.

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

### 7. Report

Report the result with file path and line count.

## Important

- Do NOT update state files
- Do NOT create additional files — only write the one assigned file
- Do NOT modify the frontmatter — only add/replace body content
- Do NOT read full content of other doc files (only frontmatter was provided for cross-refs)
- If you discover a missing concept or algorithm that should exist, note it in your report but do NOT create it
- Keep the file under ~300 lines. If content exceeds this, split into subsections and note in your report which parts could become separate files
