#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ "${mode}" != "release-trigger" ] && [ "${mode}" != "release-concurrency" ] && [ "${mode}" != "workflow-names" ] && echo "❌ unsupported workflow validation mode: expected 'release-trigger', 'release-concurrency' or 'workflow-names'" >&2 && exit 1

if [ "${mode}" = "workflow-names" ]; then
  [ "$(yq -r '.name' .github/workflows/ci.yaml)" != "CI" ] && echo "❌ ci.yaml workflow name must be CI" >&2 && exit 1
  [ "$(yq -r '.name' .github/workflows/cd.yaml)" != "CD" ] && echo "❌ cd.yaml workflow name must be CD" >&2 && exit 1
  echo "✅ CI/CD workflow names conform"
  exit 0
fi

if [ "${mode}" = "release-trigger" ]; then
  yq -o=json .github/workflows/release.yaml | jq -e '.on.workflow_run.workflows == ["CI"]' >/dev/null || {
    echo "❌ release must trigger from CI" >&2
    exit 1
  }
  yq -o=json .github/workflows/release.yaml | jq -e '.on.workflow_run.branches == ["main"]' >/dev/null || {
    echo "❌ release must be limited to main" >&2
    exit 1
  }
  yq -o=json .github/workflows/release.yaml | jq -e '.on.workflow_run.types == ["completed"]' >/dev/null || {
    echo "❌ release workflow_run type must be completed" >&2
    exit 1
  }
  yq -o=json .github/workflows/release.yaml | jq -e '.jobs.release.if == "github.event.workflow_run.conclusion == '\''success'\''"' >/dev/null || {
    echo "❌ release job must require CI success" >&2
    exit 1
  }
  echo "✅ Release trigger conforms"
  exit 0
fi

yq -o=json .github/workflows/release.yaml | jq -e '.concurrency.group == "release"' >/dev/null || {
  echo "❌ release concurrency group must be release" >&2
  exit 1
}
echo "✅ Release concurrency conforms"
