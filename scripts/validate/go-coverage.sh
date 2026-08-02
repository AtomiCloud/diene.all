#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
profile="${2:-}"

[ -z "${mode}" ] && echo "❌ coverage mode not set" >&2 && exit 1
[ -z "${profile}" ] && echo "❌ coverage profile not set" >&2 && exit 1
[ ! -s "${profile}" ] && echo "❌ coverage profile '${profile}' is empty" >&2 && exit 1

marker="$(yq -r ".tiers.${mode}.pathMarker" .config/go-base.coverage.yaml)"
threshold="$(yq -r ".tiers.${mode}.threshold" .config/go-base.coverage.yaml)"
paths="$(awk 'NR > 1 {sub(/:[0-9].*/, "", $1); print $1}' "${profile}" | sort -u)"
[ -z "${paths}" ] && echo "❌ coverage profile '${profile}' has no source files" >&2 && exit 1
escaped="$(awk -v marker="${marker}" 'index($0, marker) == 0 {print; exit}' <<<"${paths}")"
[ -n "${escaped}" ] && echo "❌ ${mode} coverage escaped its '${marker}' scope" >&2 && exit 1
total="$(go tool cover -func="${profile}" | awk '/^total:/ {gsub(/%/, "", $3); print $3}')"
below="$(awk -v total="${total}" -v threshold="${threshold}" 'BEGIN {print (total + 0 < threshold + 0) ? "true" : "false"}')"
[ "${below}" = "true" ] && echo "❌ ${mode} coverage ${total}% is below ${threshold}%" >&2 && exit 1

echo "✅ ${mode} coverage is scoped and ${total}%"
