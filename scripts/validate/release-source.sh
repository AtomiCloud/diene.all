#!/usr/bin/env bash
set -euo pipefail

release_workflow="${RELEASE_WORKFLOW:-.github/workflows/release.yaml}"
yq -o=json "${release_workflow}" | jq -e '.on.workflow_run.workflows == ["CI"]' >/dev/null || {
  echo "❌ release must trigger from CI" >&2
  exit 1
}

echo "✅ Release source conforms"
