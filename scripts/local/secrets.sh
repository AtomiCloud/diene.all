#!/usr/bin/env bash
set -euo pipefail

[ "$#" -gt 0 ] && echo "❌ secrets.sh takes no arguments; it only ensures an Infisical session" >&2 && exit 1

api_url="${INFISICAL_API_URL:-https://secrets.atomi.cloud}"
export INFISICAL_API_URL="${api_url}"

if infisical user get token --silent >/dev/null 2>&1; then
  echo "✅ Already logged into Infisical at ${api_url}"
  exit 0
fi

infisical login
echo "✅ Logged into Infisical at ${api_url}"
