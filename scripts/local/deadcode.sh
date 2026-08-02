#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ -z "${mode}" ] && echo "❌ deadcode mode not set" >&2 && exit 1

runner="./scripts/local/deadcode-${mode}.sh"
[ ! -x "${runner}" ] && echo "❌ unknown deadcode mode '${mode}'" >&2 && exit 1
"${runner}"

echo "✅ Go deadcode ${mode} pass complete"
