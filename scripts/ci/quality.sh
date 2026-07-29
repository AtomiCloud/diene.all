#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/ci/setup.sh
echo "📝 Running format, lint, typecheck, and dead-code gates..."
nix fmt -- --fail-on-change
bun run lint
bun run typecheck
./node_modules/.bin/knip
./node_modules/.bin/knip --config knip.production.json
echo "✅ Static quality gates passed"
