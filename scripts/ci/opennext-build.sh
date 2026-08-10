#!/usr/bin/env bash
set -euo pipefail

# OpenNext build + wrangler dry-run per landscape (PR CI job). Layer B faro
# posture: the source-map upload step runs WITHOUT creds — the plugin is
# disabled when ATOMI_CLIENT__FARO__BUILD__KEY is absent, which is exactly the
# no-credential dry-run the DoD requires in PR CI.

./scripts/ci/setup.sh

PATH="$(pwd)/node_modules/.bin:${PATH}"
export PATH

echo "🔧 Building OpenNext artifact..."
bunx opennextjs-cloudflare build

for landscape in pichu pikachu raichu; do
  echo "🧪 wrangler dry-run for ${landscape}..."
  wrangler deploy --dry-run --env "${landscape}"
done

echo "✅ OpenNext build + wrangler dry-runs green for all landscapes"
