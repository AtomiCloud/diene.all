# Conventional Commits

This document describes the commit conventions used in the workspace template.

## Overview

We follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) for structured commit messages.

## Format

```
type(scope): description
```

### Examples

```
feat: add a workspace capability
fix: resolve a release calculation defect
dep(patch): update a pinned dependency
ci: add workflow cache validation
```

## Commit Types

Commit types and scopes are defined in `atomi_release.yaml`. The workspace
baseline uses the unified D3 vocabulary:

```text
amend, build, chore, ci, config, dep, docs, feat, fix, perf, refactor, style, test
```

**Important**: Always refer to your project's generated `CommitConventions.md` for:

- Available types
- Available scopes for each type
- Release behavior (which types trigger releases)

## Finding Your Commit Conventions

Each project generates `CommitConventions.md` from its `atomi_release.yaml` configuration using the `releaser` tool. This file contains:

1. All available commit types
2. Available scopes for each type
3. Release behavior (major/minor/patch/no-release)
4. VAE examples for applicable types

To view or regenerate the conventions after `tools/releaser` lands at C2 step
2p:

```bash
# View the generated file
cat docs/developer/CommitConventions.md

# Regenerate (if needed)
releaser conventions
```

Before step 2p, treat `atomi_release.yaml` as authoritative. The checked-in
generated document carries an explicit bootstrap notice, and the repository
does not claim that the `releaser` command is available yet.

## Release Behavior

Different commit types trigger different release levels:

- **major**: Breaking changes
- **minor**: New features, non-breaking changes
- **patch**: Bug fixes
- **no-release**: Changes that don't trigger a release

The specific behavior is defined in your project's `atomi_release.yaml` and reflected in `CommitConventions.md`.

## Release-relevant types

| Type       | Purpose               | Release    |
| ---------- | --------------------- | ---------- |
| `feat`     | New feature           | minor      |
| `fix`      | Bug fix               | patch      |
| `docs`     | Documentation changes | no-release |
| `ci`       | CI configuration      | no-release |
| `refactor` | Code refactoring      | minor      |
| `test`     | Adding/updating tests | minor      |
| `build`    | Build system changes  | no-release |

## Breaking Changes

To indicate a breaking change, add `!` after the type/scope or add `BREAKING CHANGE:` footer:

```
feat!: remove deprecated behavior

or

feat: add replacement behavior

BREAKING CHANGE: This changes the API contract
```

## Summary

| Aspect            | Pattern                                      |
| ----------------- | -------------------------------------------- |
| **Format**        | `type(scope): description`                   |
| **Configuration** | `atomi_release.yaml`                         |
| **Reference**     | `docs/developer/CommitConventions.md`        |
| **Release**       | Type-specific (major/minor/patch/no-release) |
| **Breaking**      | Add `!` or `BREAKING CHANGE:` footer         |
