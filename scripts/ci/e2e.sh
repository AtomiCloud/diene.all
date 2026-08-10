#!/usr/bin/env bash
set -euo pipefail

# E2E job: Playwright browser journeys + Bruno API collection against a real
# standalone server (next build output, the same server the Garden rail boots).

./scripts/ci/setup.sh

PATH="$(pwd)/node_modules/.bin:${PATH}"
export PATH

echo "🔧 Building the app for e2e..."
next build
./scripts/local/standalone-assets.sh

echo "🧪 Running Playwright journeys (webServer boots the standalone server)..."
if [[ ! -d ${PLAYWRIGHT_BROWSERS_PATH:-/nonexistent} ]]; then
  echo "❌ PLAYWRIGHT_BROWSERS_PATH is unset or not a directory — the Nix dev shell must provide the Playwright browsers (nix/packages.nix playwright-browsers)" >&2
  exit 1
fi
playwright test

./scripts/ci/bruno.sh

echo "✅ E2E suites green"
