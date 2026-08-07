---
id: taskfile
title: Taskfile Conventions
---

# Taskfile Conventions

`task` (go-task) is the repository task runner — the only one. Root tasks live in
`Taskfile.yaml`; grouped tasks live under `tasks/` and are included by namespace.

## Reading the task surface

`task --list` prints every available task with its description; that output is the
current surface. To read it from source instead, start at `Taskfile.yaml`: its
`includes:` block maps each namespace to a file under `tasks/`, so a task shown as
`<namespace>:<task>` is the `<task>` key in the file that namespace includes.
Every task carries a `desc:` explaining what it does, and its `cmds:` are the
literal commands it runs.

The root `setup` task owns generated workspace assets. It runs
`releaser conventions -c release.yaml` and then the only permitted vendor-tree
writer, `skills-sync sync --tier setup`. Setup is repair-capable; the pre-commit
and CI tiers refuse rather than silently staging or repairing a commit.

Docker and Helm tasks are keyed by the artifact they act on — one task set per
Dockerfile and per chart. See [the Docker standard](../docker/index.md) and
[the Helm standard](../helm/index.md) for that naming convention.

## Rules

1. Keep one- or two-line commands inline in Taskfiles.
2. Move conditional or multi-step local logic to `scripts/local/`.
3. Never call `scripts/ci/*` from a Taskfile; workflows own those entry points.
4. Use lowercase names and colon-separated namespaces.
5. Put repository-specific image and chart values in Taskfile `vars:` blocks,
   scoped to the task that uses them rather than shared across artifacts.
6. Do not add progress-only `echo` commands; the runner already displays each
   command.

Each include remains self-contained so downstream strips can remove only their own
axis.
