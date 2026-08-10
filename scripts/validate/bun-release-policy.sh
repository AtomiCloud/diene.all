#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ "${mode}" != "trigger" ] && [ "${mode}" != "credential" ] && [ "${mode}" != "command" ] && echo "❌ Usage: bun-release-policy.sh <trigger|credential|command>" >&2 && exit 1

if [ "${mode}" = "trigger" ]; then
  [ "$(yq -r '.on.push.tags[0]' .github/workflows/cd.yaml)" != "v*.*.*" ] && echo "❌ CD publish trigger must be v*.*.*" >&2 && exit 1
  echo "✅ Publish tag policy conforms"
  exit 0
fi

if [ "${mode}" = "credential" ]; then
  expected_secret_expression='$'"{{ secrets.NPM_API_KEY }}"
  [ "$(yq -r '.on.workflow_call.secrets.NPM_API_KEY.required' .github/workflows/⚡reusable-publish.yaml)" != "true" ] && echo "❌ reusable publish workflow must require NPM_API_KEY" >&2 && exit 1
  [ "$(yq -r '.jobs.publish.steps[] | select(.name == "Publish library") | .env.NPM_API_KEY' .github/workflows/⚡reusable-publish.yaml)" != "${expected_secret_expression}" ] && echo "❌ publish path must forward the NPM_API_KEY org secret" >&2 && exit 1
  rg -q 'NPM_API_KEY' scripts/ci/publish.sh || {
    echo "❌ publish script does not consume NPM_API_KEY" >&2
    exit 1
  }
  echo "✅ Publish credential policy conforms"
  exit 0
fi

rg -F 'bun publish --access public --tolerate-republish' scripts/ci/publish.sh >/dev/null || {
  echo "❌ publish command must use public and tolerate-republish flags" >&2
  exit 1
}
echo "✅ Publish command policy conforms"
