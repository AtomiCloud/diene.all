#!/usr/bin/env bash
set -euo pipefail

# Weekly standby synthetic probe: one real request against the standby host.
# A missing STANDBY_URL is a configuration failure, not a skip — silence here
# would hide a dead standby.

standby_url="${1:?STANDBY_URL required}"

echo "🩺 Probing standby: ${standby_url}"
status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "${standby_url}")"

if [[ ${status} -ge 200 && ${status} -lt 400 ]]; then
  echo "✅ Standby serving (HTTP ${status})"
else
  echo "❌ Standby probe failed (HTTP ${status})" >&2
  exit 1
fi
