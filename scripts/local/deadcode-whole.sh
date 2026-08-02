#!/usr/bin/env bash
set -euo pipefail

echo "🔍 Running whole-repository staticcheck with test analysis"
staticcheck -tests=true ./...

echo "🔍 Running whole-repository deadcode with test reachability"
report="$(deadcode -json -test ./...)"
# deadcode prints `null` when it finds nothing, so an empty report means it never looked.
[ -z "${report}" ] && echo "❌ whole-repository deadcode produced no report" >&2 && exit 1
count="$(jq '(. // []) | length' <<<"${report}")"
[ "${count}" -ne 0 ] && jq . <<<"${report}" >&2 && exit 1

echo "✅ Go deadcode whole pass complete"
