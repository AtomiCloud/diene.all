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
| `CI`      | pushes, pull requests, manual runs | pre-commit, Docker, and Helm lanes     |
| `Release` | successful `CI` run on `main`      | semantic versioning and GitHub release |
| `CD`      | one `v*.*.*` tag pattern           | versioned Docker image and Helm chart  |

Callers grant permissions, pass only repository-specific values, and use
`secrets: inherit`. Reusable workflows own setup and invoke exactly one existing
CI script.

## Reusable workflows

- `⚡reusable-precommit.yaml` runs `scripts/ci/pre-commit.sh` in `.#ci`.
- `⚡reusable-docker.yaml` runs `scripts/ci/docker.sh` in `.#cd`.
- `⚡reusable-helm.yaml` runs `scripts/ci/helm.sh` in `.#cd`.
- `⚡reusable-release.yaml` runs `scripts/ci/release.sh` in `.#releaser`.

`AtomiCloud/actions.setup-nix@v3` checks out the repository, so do not add an
adjacent `actions/checkout`. Docker additionally uses
`AtomiCloud/actions.setup-docker@v2`.

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
nix develop .#cd -c ./scripts/ci/docker.sh
nix develop .#cd -c ./scripts/ci/helm.sh
```

The Docker and Helm scripts build locally by default. Their reusable workflows
set the documented environment contract to enable publishing.

## Artifact publishing

Docker and Helm callers pass per-repository image or chart values through
workflow `with:` inputs. Empty release versions produce commit builds; CD passes
the tag as the version. Add another image or chart as another caller job rather
than putting repository-specific branching into the reusable workflow.

Release execution is wired now but awaits the C2 step-2p `tools/releaser` fold;
the workspace does not claim a working `releaser` binary before then.
