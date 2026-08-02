#!/usr/bin/env bash
set -euo pipefail

staticcheck -tests=false ./...
report="$(deadcode -json ./...)"
count="$(jq '(. // []) | length' <<<"${report}")"
[ "${count}" -ne 0 ] && jq . <<<"${report}" >&2 && exit 1

echo "✅ Go deadcode production pass complete"
