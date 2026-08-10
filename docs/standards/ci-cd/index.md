---
id: ci-cd
title: CI/CD Workflows
---

# CI/CD Workflows

GitHub Actions supplies triggers, permissions, runners, and inputs. Repository
logic stays in executable `scripts/ci/*.sh` files and runs through the matching
Nix shell.

## Workflow split

| Workflow  | Trigger                            | Responsibility                                   |
| --------- | ---------------------------------- | ------------------------------------------------ |
| `CI`      | pushes, pull requests, manual runs | source gates, binaries, binary SIT, native smoke |
| `Release` | successful `CI` run on `main`      | version, assets, commit, tag, atomic push        |
| `CD`      | one `v*.*.*` tag pattern           | Nix validation and GoReleaser channels           |

Callers grant permissions, pass only repository-specific values, and use
`secrets: inherit`. Reusable workflows own setup and invoke exactly one existing
CI script.

## Reusable workflows

- `⚡reusable-precommit.yaml` runs `scripts/ci/pre-commit.sh` in `.#ci`.
- `⚡reusable-test.yaml` runs the 100%-coverage unit or integration entrypoint.
- `⚡reusable-build.yaml` validates the Bun bundle.
- `⚡reusable-compile.yaml` cross-compiles three binaries and uploads one tar
  archive so executable modes survive transport.
- `⚡reusable-sit.yaml` extracts that archive and runs SIT with
  `SIT_DRIVER=binary`.
- `⚡reusable-smoke.yaml` directly executes Linux x64, Linux arm64, and Darwin
  arm64 artifacts on their three native runners.
- `⚡reusable-release.yaml` runs `scripts/ci/release.sh` in `.#releaser`.

`AtomiCloud/actions.setup-nix@v3` checks out the repository, so do not add an
adjacent `actions/checkout`. The native smoke workflow is the exception: it
uses a credential-free checkout because it executes the transported artifact
without the Nix setup action.

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
env BUN_INSTALL_OFFLINE=1 ./scripts/ci/test.sh unit
env BUN_INSTALL_OFFLINE=1 ./scripts/ci/test.sh int
env CLI_BIN=dist/bin/releaser-linux-x64-baseline BUN_INSTALL_OFFLINE=1 ./scripts/ci/test.sh sit
```

The Docker script builds locally by default. Its reusable workflow sets the
documented environment contract to enable publishing.

## Artifact publishing

CD first builds `.#releaser`, then `scripts/release/publish.sh` compiles and
hands the prebuilt binaries to GoReleaser. Supported channels are three
mode-preserving archives, checksums, deb/rpm packages, a Homebrew cask, GitHub
release assets, the installer, and Fury packages. CI never publishes and this
repository has no Docker job or image channel.
