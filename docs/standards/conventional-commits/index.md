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

## Reading the vocabulary

`atomi_release.yaml` owns the commit types, their scopes, and what each one does
to the version. Read its `types:` list like this:

- each entry's `type:` is the word before the colon in a commit subject, and its
  `desc:` says when to use it;
- each entry's `scopes:` map gives the scopes valid for that type. `default:`
  applies when you write no scope at all; any other key is a scope you may put in
  parentheses, as in `dep(patch):`;
- each scope's `release:` value is the version bump it causes — `major`, `minor`,
  `patch`, or `false` for no release;
- an optional `section:` is the changelog heading that type's commits group under.

`specialScopes:` at the top level are scopes usable with any type. Both commit
validation and release calculation consume this same file, so the vocabularies
cannot drift independently.

## Finding your generated conventions

Each project generates a commit-conventions document from `atomi_release.yaml`
using the `releaser` tool. Its output path is the `conventionMarkdown.path` value
in `atomi_release.yaml`:

```bash
# View the generated file
cat "$(yq -r '.conventionMarkdown.path' atomi_release.yaml)"

# Regenerate (if needed)
releaser conventions
```

`atomi_release.yaml` remains the machine-readable source of truth; the
immutable releaser v1.0.0 flake input makes the command available locally.

## Breaking Changes

To indicate a breaking change, add `!` after the type/scope or add a breaking
footer:

```
feat!: remove deprecated behavior

or

feat: add replacement behavior

BREAKING CHANGE: This changes the API contract
```

The footer keywords that count as breaking are the `keywords:` list in
`atomi_release.yaml`.

## Summary

| Aspect            | Pattern                                               |
| ----------------- | ----------------------------------------------------- |
| **Format**        | `type(scope): description`                            |
| **Configuration** | `atomi_release.yaml`                                  |
| **Reference**     | the file named by its `conventionMarkdown.path`       |
| **Release**       | each scope's `release:` value in `atomi_release.yaml` |
| **Breaking**      | Add `!` or a footer keyword from `keywords:`          |
