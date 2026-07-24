# Releaser domain

## Boundary

`releaser` turns one strict configuration and reachable Git history into a
version decision, deterministic Markdown notes, and—only for a real release—a
sequenced set of local and remote side effects. Linting and release analysis use
the same normalized type/scope vocabulary.

## Configuration

Schema v2 is canonical. Legacy v1 documents translate only the changelog, exec,
git, and GitHub modules demonstrated by existing consumers. Unknown modules and
unsupported lifecycle keys fail with guidance to use explicit prepare/success
hooks. Migration writes v2 atomically before deleting `.gitlint` and generated
`.releaserc.yaml` files.

## Release calculation

The greatest stable reachable tag matching `tagFormat` is the baseline. Parsed
commits request major, minor, patch, or no release through breaking markers,
special scopes, explicit scopes, and default scopes in that order. Unknown or
malformed historical commits request no release. The first requested release is
always `1.0.0`.

## Side-effect order

A real release requires an allowed branch and clean tree, then runs before-write
hooks, writes conventions and changelog, runs after-write hooks, enforces the
lockfile and configured-asset fences, commits, tags, atomically pushes branch and
tag, optionally performs GitHub release/comment/label calls, runs success hooks,
and verifies a clean result. Failures stop later phases; public history is never
force-rewritten or rolled back.

Dry-run release, `next`, and `changelog` perform read-only computation. The core
never invokes a package manager or loads runtime plugins.
