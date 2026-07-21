#!/usr/bin/env bash
set -euo pipefail

ci_workflow="${CI_WORKFLOW:-.github/workflows/ci.yaml}"
cd_workflow="${CD_WORKFLOW:-.github/workflows/cd.yaml}"
[ "$(yq -r '.name' "${ci_workflow}")" = "CI" ] || {
  echo "❌ ci.yaml workflow name must be CI" >&2
  exit 1
}
[ "$(yq -r '.name' "${cd_workflow}")" = "CD" ] || {
  echo "❌ cd.yaml workflow name must be CD" >&2
  exit 1
}

echo "✅ CI/CD workflow names conform"
