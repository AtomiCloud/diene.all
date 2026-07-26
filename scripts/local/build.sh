#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
artifact="dist/go-consumer"

mkdir -p dist
echo "🔨 Building Go consumer artifact ${artifact}..."
go build -trimpath -o "${artifact}" ./cmd/go-consumer

[ ! -x "${artifact}" ] && echo "❌ Build artifact missing or not executable: ${artifact}" >&2 && exit 1
echo "✅ Go consumer artifact built: ${artifact}"
