#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

artifact="dist/index.js"

./scripts/local/schema-gen.sh
mkdir -p infra/primordial_chart/files
./scripts/local/problems-export.sh --out infra/primordial_chart/files/problems.json
echo "🔨 Building sample bundle..."
bun build ./src/index.ts --outdir ./dist --target bun

[[ ! -f ${artifact} ]] && echo "❌ Build artifact missing: ${artifact}" >&2 && exit 1
echo "✅ Build artifact present: ${artifact}"
