#!/usr/bin/env bash
set -euo pipefail

action="${1:-}"
api_url="${INFISICAL_API_URL:-https://secrets.atomi.cloud}"

[ -z "${action}" ] && echo "❌ action must be 'fetch' or 'scan'" >&2 && exit 1

case "${action}" in
fetch)
  [ -z "${INFISICAL_PROJECT_ID:-}" ] && echo "❌ 'INFISICAL_PROJECT_ID' env var not set" >&2 && exit 1
  [ -z "${INFISICAL_ENVIRONMENT:-}" ] && echo "❌ 'INFISICAL_ENVIRONMENT' env var not set" >&2 && exit 1
  if ! INFISICAL_API_URL="${api_url}" infisical user get token --silent >/dev/null 2>&1; then
    INFISICAL_API_URL="${api_url}" infisical login
  fi
  INFISICAL_API_URL="${api_url}" infisical export --projectId="${INFISICAL_PROJECT_ID}" --env="${INFISICAL_ENVIRONMENT}" --format=dotenv >.env
  ;;
scan)
  INFISICAL_API_URL="${api_url}" infisical scan . -v
  ;;
*)
  echo "❌ unsupported secrets action '${action}'" >&2
  exit 1
  ;;
esac

echo "✅ Secrets ${action} complete"
