#!/usr/bin/env bash
set -euo pipefail

# Bruno API collection against the real standalone server. Standalone slice of
# the e2e job so the API contract can be exercised (and sabotaged) on its own;
# expects `next build` + standalone-assets to have run already, and builds them
# itself when absent.

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

PATH="$(pwd)/node_modules/.bin:${PATH}"
export PATH

if [[ ! -f .next/standalone/server.js ]]; then
  echo "🔧 Building the app for the Bruno collection..."
  next build
  ./scripts/local/standalone-assets.sh
fi

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

echo "✅ Bruno collection green"
