---
id: taskfile
title: Taskfile Conventions
---

# Taskfile Conventions

`pls` is the repository task runner. Root tasks live in `Taskfile.yaml`; grouped
tasks live under `tasks/` and are included by namespace.

## Current surface

| Command            | Purpose                                  |
| ------------------ | ---------------------------------------- |
| `pls setup`        | synchronize generated vendored skills    |
| `pls lint`         | run all pre-commit gates                 |
| `pls skills:sync`  | rebuild `.claude/skills/vendor/`         |
| `pls secret:fetch` | fetch the selected Infisical environment |
| `pls secret:scan`  | scan tracked content for secrets         |

## Rules

1. Keep one- or two-line commands inline in Taskfiles.
2. Move conditional or multi-step local logic to `scripts/local/`.
3. Never call `scripts/ci/*` from a Taskfile; workflows own those entry points.
4. Use lowercase names and colon-separated namespaces.
5. Do not add progress-only `echo` commands; the runner already displays each
   command.

The root file includes the `secret` task file. Each include
and many-owner block remains self-contained so downstream strips can remove only
their own axis.
