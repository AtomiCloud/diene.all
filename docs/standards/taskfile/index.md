---
id: taskfile
title: Taskfile Conventions
---

# Taskfile Conventions

`pls` is the repository task runner. Root tasks live in `Taskfile.yaml`; grouped
tasks live under `tasks/` and are included by namespace.

## Current surface

| Command                   | Purpose                                      |
| ------------------------- | -------------------------------------------- |
| `pls setup`               | synchronize skills and frozen dependencies   |
| `pls lint`                | run all pre-commit gates                     |
| `pls test`                | run unit, integration, and compiled SIT      |
| `pls test:{unit,int,sit}` | run one test tier                            |
| `pls test:*:coverage`     | write the selected LCOV ledger               |
| `pls build`               | bundle `bin/releaser.ts` into `dist/`        |
| `pls compile`             | compile the three standalone targets         |
| `pls run -- <args>`       | run the source composition root              |
| `pls preview -- <args>`   | run the compiled host binary                 |
| `pls deadcode`            | run strict and review dead-code analysis     |
| `pls skills:sync`         | rebuild `.claude/skills/vendor/`             |
| `pls secret:{fetch,scan}` | fetch an environment or scan tracked content |
| `pls clean`               | remove local Bun build/test artifacts        |

## Rules

1. Keep one- or two-line commands inline in Taskfiles.
2. Move conditional or multi-step local logic to `scripts/local/`.
3. Never call `scripts/ci/*` from a Taskfile; workflows own those entry points.
4. Use lowercase names and colon-separated namespaces.
5. Put repository-specific artifact values in Taskfile `vars:` blocks.
6. Do not add progress-only `echo` commands; the runner already displays each
   command.

The root file includes compile, secret, unit, and integration task groups. It
intentionally has no Docker include or image task: the releaser distribution is
Nix plus GoReleaser channels.
