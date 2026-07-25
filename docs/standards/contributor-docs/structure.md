# Contributor Docs Structure

The folder layout for contributor documentation. All files use `.mdx` extension to support MDX features and Mermaid diagrams.

---

## Top-Level Structure

```text
docs/contributor/
├── 00-overview.mdx              # Project intro, manifest of all docs
├── 01-architecture/
│   ├── index.mdx                # Architecture overview, diagrams
│   └── adr-NNN-<decision>.mdx   # Individual ADRs (numbered, dated)
├── 02-modules.mdx               # Module map: names, boundaries, relationships
├── 03-development/
│   ├── index.mdx                # Dev setup, workflow overview
│   ├── folder-structure.mdx     # Repo layout explanation
│   └── commands.mdx             # Taskfile/Makefile commands
├── <module-name>/               # One folder per module
│   ├── overview.mdx
│   ├── features/
│   │   ├── index.mdx
│   │   └── <feature>.mdx
│   ├── concepts/
│   │   ├── index.mdx
│   │   └── <concept>.mdx
│   ├── algorithms/
│   │   ├── index.mdx
│   │   └── <algorithm>.mdx
│   └── surfaces/
│       ├── index.mdx
│       └── <surface>.mdx
└── shared/                      # Cross-module content
    ├── concepts/
    │   ├── index.mdx
    │   └── <concept>.mdx
    └── algorithms/
        ├── index.mdx
        └── <algorithm>.mdx
```

---

## File Roles

### Top-Level Files

| File                            | Role                                                                                      |
| ------------------------------- | ----------------------------------------------------------------------------------------- |
| `00-overview.mdx`               | Entry point. Project summary, tech stack, links to all modules. The LLM reads this first. |
| `01-architecture/index.mdx`     | High-level architecture: system diagram, component relationships, deployment topology.    |
| `01-architecture/adr-NNN-*.mdx` | Individual Architecture Decision Records. Numbered sequentially, dated.                   |
| `02-modules.mdx`                | Module map: lists all modules, their purpose, boundaries, and inter-module dependencies.  |
| `03-development/`               | Developer onboarding: folder structure, available commands, development workflow.         |

### Per-Module Files

| File                    | Role                                                                                                    |
| ----------------------- | ------------------------------------------------------------------------------------------------------- |
| `overview.mdx`          | **Narrative**: what the module does, what it owns, what it doesn't. Links to key features and concepts. |
| `features/index.mdx`    | **Map**: groups features, shows relationships between them. Pure navigation.                            |
| `features/<name>.mdx`   | Individual feature: behavior, configuration, constraints. Links to concepts/algorithms/surfaces.        |
| `concepts/index.mdx`    | **Map**: groups concepts by type, shows how they relate.                                                |
| `concepts/<name>.mdx`   | Individual concept: context, explanation, decision (if applicable).                                     |
| `algorithms/index.mdx`  | **Map**: groups algorithms, shows which features use them.                                              |
| `algorithms/<name>.mdx` | Individual algorithm: problem, approach, why this way, trade-offs.                                      |
| `surfaces/index.mdx`    | **Map**: groups surfaces by type (API, CLI, SDK, event).                                                |
| `surfaces/<name>.mdx`   | Individual surface: endpoint/command details, request/response, errors.                                 |

### Overview vs Index

These serve different roles and must not overlap:

| File           | Role                                                      | Content Style        |
| -------------- | --------------------------------------------------------- | -------------------- |
| `overview.mdx` | **Narrative** -- tells the story of what the module is    | Paragraphs, diagrams |
| `*/index.mdx`  | **Map** -- shows what exists and how items group together | Lists, tables, links |

---

## Naming Conventions

- **Module folders**: kebab-case matching the bounded context name (e.g., `user-management/`, `payment-processing/`)
- **Feature files**: kebab-case describing the capability (e.g., `webhook-retry.mdx`, `cache-invalidation.mdx`)
- **Concept files**: kebab-case, optionally prefixed by type (e.g., `rest-vs-graphql.mdx`, `auth-flow.mdx`, `oauth-basics.mdx`)
- **Algorithm files**: kebab-case describing the algorithm (e.g., `token-bucket-rate-limiting.mdx`)
- **Surface files**: kebab-case describing the endpoint/command (e.g., `get-user-by-id.mdx`, `cache-clear.mdx`)
- **ADR files**: `adr-NNN-<kebab-case-title>.mdx` (e.g., `adr-001-use-postgresql.mdx`)

---

## Section Folders Are Optional

Not every module needs all four section folders. Only create a section folder when the module has content for it:

- A simple CRUD module might only have `features/` and `surfaces/`
- A module with complex internals might have `algorithms/` but no `surfaces/`
- `concepts/` and `algorithms/` are only needed when there's something non-obvious to explain

---

## Cross-References

All cross-references use **relative MDX paths**:

```mdx
See [Caching Concept](../concepts/cache-invalidation.mdx) for why we chose this approach.
```

Never use plain text names like "see the caching concept." Always link with a file path so both humans and LLMs can follow.
