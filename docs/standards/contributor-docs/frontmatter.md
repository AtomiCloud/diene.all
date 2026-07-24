# Frontmatter Schemas

Every contributor doc file starts with YAML frontmatter. Frontmatter serves two purposes: structured metadata for tooling and a quick-scan summary for LLMs that can decide whether to read the full file.

---

## Features

```yaml
---
title: 'Feature Name'
description: 'One-line summary of what this feature does'
date: 2026-03-03
status: draft # draft | stable | deprecated
tags: [performance, cache]
concepts: # Paths to concept files this feature relies on
  - ../concepts/cache-invalidation.mdx
algorithms: # Paths to algorithm files this feature uses
  - ../algorithms/lru-eviction.mdx
surfaces: # Paths to surface files that expose this feature
  - ../surfaces/get-cache-entry.mdx
---
```

Features are the **hub** -- they link outward to concepts, algorithms, and surfaces using dedicated fields. This creates a clear navigation direction: start at a feature, fan out to details.

---

## Concepts

```yaml
---
title: 'Concept Name'
description: 'One-line summary'
date: 2026-03-03
status: stable # draft | stable | deprecated
type: comparison # comparison | flow | design | prereq
tags: [auth, security]
related: # Paths to any related files (concepts, algorithms, etc.)
  - ../concepts/oauth-vs-jwt.mdx
  - ../algorithms/token-refresh.mdx
---
```

The `type` field categorizes the concept:

| Type         | Use When                                                       |
| ------------ | -------------------------------------------------------------- |
| `comparison` | Evaluating X vs Y, with a comparison table                     |
| `flow`       | Describing an end-to-end process                               |
| `design`     | Explaining an architectural pattern or design decision         |
| `prereq`     | Providing background knowledge needed to understand other docs |

---

## Algorithms

```yaml
---
title: 'Algorithm Name'
description: 'One-line summary of what this algorithm accomplishes'
date: 2026-03-03
status: stable # draft | stable | deprecated
tags: [scheduling, optimization]
related:
  - ../concepts/eventual-consistency.mdx
  - ../algorithms/conflict-resolution.mdx
---
```

---

## Surfaces

```yaml
---
title: 'Surface Name'
description: 'One-line summary'
date: 2026-03-03
status: stable # draft | stable | deprecated
type: api # api | cli | sdk | event
method: GET # API surfaces only
path: /v1/users/:id # API surfaces only
command: cache clear # CLI surfaces only
tags: [users, read]
related:
  - ../surfaces/list-users.mdx
---
```

Type-specific fields:

| Surface Type | Extra Fields                              |
| ------------ | ----------------------------------------- |
| `api`        | `method` (HTTP method), `path` (URL path) |
| `cli`        | `command` (CLI command string)            |
| `sdk`        | None (describe in body)                   |
| `event`      | None (describe in body)                   |

---

## ADRs

```yaml
---
title: 'ADR-001: Decision Title'
description: 'One-line summary of the decision'
date: 2026-03-03
status: accepted # proposed | accepted | superseded | deprecated
superseded_by: adr-003-use-redis.mdx # Only if status is superseded
tags: [database, scaling]
related:
  - adr-001-use-postgres.mdx
---
```

---

## Module Overviews

```yaml
---
title: 'Module Name'
description: 'One-line summary of what this module owns'
---
```

Module overviews use minimal frontmatter since their role is narrative, not linkable metadata.

---

## Index Files

```yaml
---
title: 'Module X -- Features'
description: 'Feature map for Module X'
---
```

Index files also use minimal frontmatter.

---

## Design Principles

1. **Features are the hub.** They use dedicated `concepts`, `algorithms`, `surfaces` fields. Everything else uses generic `related`.
2. **No `module` field.** The folder path encodes the module. Duplicating it in frontmatter creates drift.
3. **`related` is generic.** Concepts can link to algorithms, algorithms to concepts, surfaces to surfaces. No type restriction.
4. **`tags` is freeform.** No controlled vocabulary at the schema level. When writing docs, reuse existing tags from sibling files to keep them consistent.
5. **`status` is universal.** All content types support `draft | stable | deprecated` to track lifecycle.
