#!/usr/bin/env bash
set -euo pipefail

echo "🔍 Running production deadcode without test reachability"
report="$(deadcode -json ./...)"
# deadcode prints `null` when it finds nothing, so an empty report means it never looked.
[ -z "${report}" ] && echo "❌ production deadcode produced no report" >&2 && exit 1
count="$(jq '(. // []) | length' <<<"${report}")"
[ "${count}" -ne 0 ] && jq . <<<"${report}" >&2 && exit 1

echo "✅ Go deadcode production pass complete"
