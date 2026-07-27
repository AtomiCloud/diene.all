#!/usr/bin/env bash
set -euo pipefail

# 📤 Landscape upload (argon pattern, CloudflareDeploy promotion policy):
# CI ONLY uploads tagged Worker versions — it never deploys to production
# directly; CloudflareDeploy promotes a pinned version out-of-band.
#
# usage: upload.sh <landscape> <tag>

landscape="${1:?landscape required (pichu|pikachu|raichu)}"
tag="${2:-}"

echo "🌍 Building for landscape binding: ${landscape}"
export ATOMI_LANDSCAPE="${landscape}"

echo "⬇️ Installing dependencies"
bun install --frozen-lockfile

PATH="$(pwd)/node_modules/.bin:${PATH}"
export PATH

echo "🔧 Building OpenNext artifact (faro source-map layer runs inside the build)..."
bunx opennextjs-cloudflare build

echo "📤 Uploading tagged Worker version to ${landscape} (never a direct deploy)..."
if [[ -n ${tag} ]]; then
  wrangler versions upload --env "${landscape}" --message "Release ${tag}"
else
  wrangler versions upload --env "${landscape}"
fi

echo "🎉 Version uploaded for ${landscape}; promotion is CloudflareDeploy's job."
