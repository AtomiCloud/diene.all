#!/usr/bin/env bash
set -euo pipefail

staticcheck -tests=true ./...
report="$(deadcode -json -test ./...)"
count="$(jq '(. // []) | length' <<<"${report}")"
[ "${count}" -ne 0 ] && jq . <<<"${report}" >&2 && exit 1

echo "✅ Go deadcode whole pass complete"
