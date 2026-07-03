#!/usr/bin/env bash
set -euo pipefail

ARTIFACT="dist/index.js"

echo "🔨 Building sample bundle..."
bun build ./src/index.ts --outdir ./dist --target bun

[ ! -f "${ARTIFACT}" ] && echo "❌ Build artifact missing: ${ARTIFACT}" >&2 && exit 1
echo "✅ Build artifact present: ${ARTIFACT}"
