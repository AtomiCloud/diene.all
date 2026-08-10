#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

# Populate the module cache first so skills-sync cannot vendor from a partial tree.
echo "📦 Downloading Go module dependencies..."
go mod download
module="$(go list -m)"
[ "${module}" != "github.com/AtomiCloud/diene.go-consumer" ] && echo "❌ Unexpected Go module: ${module}" >&2 && exit 1
echo "✅ Go module dependencies ready for ${module}"

releaser conventions -c release.yaml
skills-sync sync

echo "✅ setup completed"
