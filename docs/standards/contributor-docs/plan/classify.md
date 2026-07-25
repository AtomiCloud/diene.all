# Classify Changes — Team Agent (Opus)

## Agent Context

- Working directory: repo root
- Diff summary: `.contributor-docs/diff-summary.md`
- Previous feedback (if re-running): {reviewFeedback} from plan-state.json
- Docs references:
  - `docs/standards/contributor-docs/classification.md` — classification heuristics
  - `docs/standards/contributor-docs/structure.md` — folder structure
  - `docs/standards/contributor-docs/frontmatter.md` — frontmatter schemas

## Agent Report Format

```
RESULT: <success|error>
PLAN_FILE: .contributor-docs/doc-plan.yaml
MODULES: <count>
FEATURES: <count>
CONCEPTS: <count>
ALGORITHMS: <count>
SURFACES: <count>
ADRS: <count>
ERROR: <error message if any>
```

**Do NOT update state files.** Report back to orchestrator only.

## Task

Read the diff summary and classify every identified capability into doc types. Group into modules. Map cross-links. Output a complete documentation plan as YAML.

## Steps

### 1. Read Inputs

Read `.contributor-docs/diff-summary.md` for the analysis.
Read the classification heuristics, structure, and frontmatter docs.
If `reviewFeedback` is provided, read it and adjust accordingly.

### 2. Identify Modules

Group related capabilities into bounded contexts. Each module should own a clear domain.

### 3. Classify Each Capability

For each identified capability:

1. Determine primary doc type (feature, concept, algorithm, surface, ADR)
2. Determine secondary docs needed (does a feature also need a concept? algorithm? surfaces?)
3. Assign to a module (or `shared/` if cross-cutting)
4. Write 1-2 line description of what the file will contain
5. List the source files relevant to this doc

### 4. Map Cross-Links

For each planned doc file, identify:

- Which concepts it needs (for features)
- Which algorithms it uses (for features)
- Which surfaces expose it (for features)
- What it's related to (for concepts, algorithms, surfaces)

### 5. Assign Writing Tiers

Group files per [writing-order.md](../common/writing-order.md):

- Tier 1: overviews, ADRs, development docs
- Tier 2: concepts
- Tier 3: algorithms
- Tier 4: features
- Tier 5: surfaces
- Tier 6: index files

### 6. Write Plan File

Write `.contributor-docs/doc-plan.yaml`:

```yaml
docsRoot: docs/contributor
modules:
  - name: user-management
    description: 'User CRUD, authentication, roles'
    files:
      - path: user-management/overview.mdx
        type: module-overview
        tier: 1
        description: 'Overview of user management module'
        sources: [src/user/...]
      - path: user-management/features/user-auth.mdx
        type: feature
        tier: 4
        description: 'User authentication with JWT'
        sources: [src/user/auth.ts, src/user/jwt.ts]
        crossLinks:
          concepts: [user-management/concepts/jwt-vs-session.mdx]
          algorithms: []
          surfaces: [user-management/surfaces/post-login.mdx]
        tags: [auth, security]
      - path: user-management/concepts/jwt-vs-session.mdx
        type: concept
        conceptType: comparison
        tier: 2
        description: 'Why we chose JWT over server-side sessions'
        sources: [src/user/auth.ts]
        tags: [auth, security]

shared:
  files:
    - path: shared/concepts/error-handling-strategy.mdx
      type: concept
      conceptType: design
      tier: 2
      description: 'Cross-cutting error handling approach'
      sources: [src/lib/errors.ts]
      tags: [errors]

topLevel:
  - path: 00-overview.mdx
    tier: 1
    description: 'Project overview'
  - path: 01-architecture/index.mdx
    tier: 1
    description: 'Architecture overview'
  - path: 02-modules.mdx
    tier: 1
    description: 'Module map'
  - path: 03-development/index.mdx
    tier: 1
    description: 'Development setup'
  - path: 03-development/folder-structure.mdx
    tier: 1
    description: 'Repository folder structure'
  - path: 03-development/commands.mdx
    tier: 1
    description: 'Available commands'

adrs:
  - path: 01-architecture/adr-001-use-jwt.mdx
    tier: 1
    description: 'Decision to use JWT for authentication'
    sources: [src/user/auth.ts]
    tags: [auth, architecture]

indexes:
  - path: user-management/features/index.mdx
    tier: 6
  - path: user-management/concepts/index.mdx
    tier: 6
```

### 7. Report

Report the result with counts per doc type.

## Resumability

- If `.contributor-docs/doc-plan.yaml` exists and no reviewFeedback: report success
- If reviewFeedback present: re-read and revise the plan
- If no plan: start from Step 1

## Important

- Do NOT update state files
- Do NOT create documentation files — only the plan YAML
- Do NOT scaffold files — that's the next phase
