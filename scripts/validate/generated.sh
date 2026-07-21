#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ "${mode}" != "sdk" ] && echo "❌ mode must be sdk" >&2 && exit 1

./scripts/local/generate-sdk.sh
git diff --exit-code -- lib/src/generated || {
  echo "❌ generated OA3 client is stale — run ./scripts/local/generate-sdk.sh" >&2
  exit 1
}

echo "✅ generated OA3 client is fresh"
