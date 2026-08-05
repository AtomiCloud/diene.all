# Commit conventions

This repository follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

- `atomi_release.yaml` is the machine-readable source of truth: it owns the
  commit types, the scopes valid for each one, and the version bump each scope
  causes.
- [The conventional-commits standard](../standards/conventional-commits/index.md)
  explains how to read that vocabulary and how to mark a breaking change.

## Status of this file

This file is currently maintained by hand.

`atomi_release.yaml` names this path in its `conventionMarkdown.path` value, so
once the `releaser` tool ships, `releaser conventions` generates this file from
that configuration. From then on it is generated output: change
`atomi_release.yaml` and regenerate rather than editing this file.
