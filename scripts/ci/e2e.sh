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
playwright install --with-deps chromium >/dev/null 2>&1 || playwright install chromium
playwright test

./scripts/ci/bruno.sh

echo "✅ E2E suites green"
