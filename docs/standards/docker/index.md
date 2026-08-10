# Docker boundary

Docker distribution is intentionally unsupported for this materialized
`releaser` CLI. The product must execute Git and repository-configured host
hooks, which is not a truthful fit for the inherited distroless/help-only image.

The repository therefore has no `infra/Dockerfile`, Docker Taskfile include,
`scripts/ci/docker.sh`, reusable Docker workflow, image CI job, or image
publication channel. Do not add one without a new product decision that
addresses Git credentials, host hooks, and executable artifact parity.

Supported distribution is the local Nix package plus GoReleaser's Linux/Darwin
archives, checksums, deb/rpm packages, Homebrew cask, installer, GitHub release
assets, and Fury packages.
