#!/usr/bin/env bash
set -euo pipefail

# Populate the module cache first so skills-sync cannot vendor from a partial tree.
go mod download

releaser conventions -c release.yaml
skills-sync sync

echo "✅ setup completed"
