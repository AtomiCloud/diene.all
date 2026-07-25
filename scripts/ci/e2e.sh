#!/usr/bin/env bash
set -euo pipefail

# E2E job: Playwright browser journeys + Bruno API collection against a real
# standalone server (next build output, the same server the Garden rail boots).

./scripts/ci/setup.sh

PATH="$(pwd)/node_modules/.bin:${PATH}"
export PATH

echo "🔧 Building the app for e2e..."
next build

echo "🧪 Running Playwright journeys (webServer boots the standalone server)..."
playwright install --with-deps chromium >/dev/null 2>&1 || playwright install chromium
playwright test

echo "🧪 Running Bruno API collection..."
server_log="$(mktemp)"
ATOMI_LANDSCAPE=base PORT=3100 HOSTNAME=127.0.0.1 node .next/standalone/server.js >"${server_log}" 2>&1 &
server_pid=$!
trap 'kill "${server_pid}" 2>/dev/null || true' EXIT
for _ in $(seq 1 60); do
  curl -fsS http://127.0.0.1:3100/api/manifest >/dev/null 2>&1 && break
  sleep 1
done
(cd tests/sit/bruno && bru run --env local --bail)

echo "✅ E2E suites green"
