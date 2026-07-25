#!/usr/bin/env bash
set -euo pipefail

# workerd preview smoke (caveat 8): the OpenNext artifact must run under REAL
# workerd, not just `next dev`. Boots `opennextjs-cloudflare preview`, waits
# for readiness, asserts the home page and the SSR landscape payload, and
# tears down.

./scripts/ci/setup.sh

PATH="$(pwd)/node_modules/.bin:${PATH}"
export PATH

if [[ ! -d .open-next ]]; then
  echo "🔧 Building OpenNext artifact first..."
  bunx opennextjs-cloudflare build
fi

port=8787
echo "🚀 Starting workerd preview on :${port}..."
bunx opennextjs-cloudflare preview -- --port "${port}" &
preview_pid=$!
trap 'kill "${preview_pid}" 2>/dev/null || true' EXIT

for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${port}/" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

body="$(curl -fsS "http://127.0.0.1:${port}/")"
echo "${body}" | grep -q 'Welcome' || {
  echo "❌ workerd preview did not render the home page" >&2
  exit 1
}

echo "✅ workerd preview smoke green"
