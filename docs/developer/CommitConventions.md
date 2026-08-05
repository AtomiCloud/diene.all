# Commit conventions

This repository follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

- `atomi_release.yaml` is the machine-readable source of truth: it owns the
  commit types, the scopes valid for each one, and the version bump each scope
  causes.
- [The conventional-commits standard](../standards/conventional-commits/index.md)
  explains how to read that vocabulary and how to mark a breaking change.

## Status of this file

This file is generated. `atomi_release.yaml` names this path in its
`conventions.path` value, `releaser conventions` writes it, and a release run
rewrites it as well. Change `atomi_release.yaml` and regenerate rather than
editing this file: everything above the next heading comes from that file's
`conventions.template`, and everything below it is generated from the commit
vocabulary.

Use `type(scope)!: subject`. Omit `(scope)` only when the type's `default` scope applies.



## Types

| Type | Description | Release |
| --- | --- | --- |
| `amend` | Small amendments and typo fixes | no release |
| `build` | Build-system changes | no release |
| `chore` | Repository chores | no release |
| `ci` | CI/CD changes | no release |
| `config` | Configuration changes | no release |
| `dep` | Dependency updates | scope-dependent |
| `docs` | Documentation changes | no release |
| `feat` | New features | scope-dependent |
| `fix` | Bug fixes | patch |
| `perf` | Performance improvements | patch |
| `refactor` | Refactors | minor |
| `style` | Non-functional style changes | patch |
| `test` | Test changes | minor |

## Scopes



### `amend` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Amend existing work | no release |

### `build` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Update build machinery | no release |

### `chore` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Perform a chore | no release |

### `ci` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Update CI/CD | no release |

### `config` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Update configuration | no release |

### `dep` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Update a dependency | no release |
| `patch` | Patch dependency update | patch |
| `minor` | Minor dependency update | minor |
| `major` | Major dependency update | major |

### `docs` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Update documentation | no release |

### `feat` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Add a feature | minor |
| `breaking` | Add a breaking feature | major |

### `fix` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Fix a bug | patch |

### `perf` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Improve performance | patch |

### `refactor` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Refactor implementation | minor |

### `style` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Update style | patch |

### `test` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Add or correct tests | minor |

## Special scopes

| Scope | Description | Release |
| --- | --- | --- |
| `no-release` | Prevent release from happening | no release |

## V.A.E. guidance

No V.A.E. guidance is configured.
