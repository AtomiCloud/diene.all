#!/usr/bin/env bash
set -euo pipefail

release_workflow="${RELEASE_WORKFLOW:-.github/workflows/release.yaml}"
yq -o=json "${release_workflow}" | jq -e '.concurrency.group == "release"' >/dev/null || {
  echo "❌ release concurrency group must be release" >&2
  exit 1
}

echo "✅ Release concurrency conforms"
