#!/usr/bin/env bash
set -euo pipefail

release_workflow="${RELEASE_WORKFLOW:-.github/workflows/release.yaml}"
yq -o=json "${release_workflow}" | jq -e '
  .on.workflow_run.branches == ["main"] and
  .on.workflow_run.types == ["completed"] and
  .jobs.release.if == "github.event.workflow_run.conclusion == '\''success'\''"
' >/dev/null || {
  echo "❌ release must be limited to successful completed main CI runs" >&2
  exit 1
}

echo "✅ Release filter conforms"
