---
id: ci-cd
title: CI/CD Workflows
---

# CI/CD Workflows

GitHub Actions supplies triggers, permissions, runners, and inputs. Repository
logic stays in executable `scripts/ci/*.sh` files and runs through the matching
Nix shell.

## Workflow split

| Workflow  | Trigger                            | Responsibility                         |
| --------- | ---------------------------------- | -------------------------------------- |
| `CI`      | pushes, pull requests, manual runs | pre-commit gates                       |
| `Release` | successful `CI` run on `main`      | semantic versioning and GitHub release |

Callers grant permissions, pass only repository-specific values, and use
`secrets: inherit`. Reusable workflows own setup and invoke exactly one existing
CI script.

## Reusable workflows

- `⚡reusable-precommit.yaml` runs `scripts/ci/pre-commit.sh` in `.#ci`.
- `⚡reusable-release.yaml` runs `scripts/ci/release.sh` in `.#releaser`.

`AtomiCloud/actions.setup-nix@v3` checks out the repository, so do not add an
adjacent `actions/checkout`.

## Pins and runners

Trusted actions (`AtomiCloud/`, `actions/`, `codecov/`, and `docker/`) use major
pins. Every other action uses an exact 40-character SHA plus its tag in a
trailing comment. Classification lives in `config/action-trust.json`.

Every nscloud Nix job carries exactly one shared tag:

```text
nscloud-cache-tag-atomi-nix-store-cache-linux-amd64
```

The organization stays constant; only runner OS and architecture vary. Never
introduce per-platform or per-service cache tags.

## Local reproduction

Use the same entry points as CI:

```bash
nix develop .#ci -c ./scripts/ci/pre-commit.sh
```

Release execution is wired now but awaits the C2 step-2p `tools/releaser` fold;
the workspace does not claim a working `releaser` binary before then.
