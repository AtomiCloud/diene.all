#!/usr/bin/env bash
set -euo pipefail

# Assemble the runnable standalone tree: `output: 'standalone'` traces the
# server and node_modules but ships neither static assets nor the runtime
# config tree. Every consumer of `.next/standalone/server.js` (Playwright
# webServer, the Bruno job, the Garden image) runs this after `next build`.

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

standalone=".next/standalone"
[[ -f ${standalone}/server.js ]] || {
  echo "❌ ${standalone}/server.js missing — run next build first" >&2
  exit 1
}

mkdir -p public
cp -r public "${standalone}/" 2>/dev/null || true
mkdir -p "${standalone}/.next"
cp -r .next/static "${standalone}/.next/"
mkdir -p "${standalone}/config"
cp config/*.yaml config/schema.json "${standalone}/config/"

echo "✅ standalone tree assembled (public/, .next/static/, config/)"
