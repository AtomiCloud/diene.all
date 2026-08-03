#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

echo "📦 Installing dependencies..."
bun install --frozen-lockfile

echo "📝 Repo dead-code review"
./node_modules/.bin/knip --config knip.llm.json --no-exit-code

echo "📝 Production dead-code review"
./node_modules/.bin/knip --config knip.production.llm.json --no-exit-code

echo "✅ Dead-code review complete"
