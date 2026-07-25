#!/usr/bin/env bash
set -euo pipefail

# Each publish-policy mode is an independently invoked S26 mechanism.
mode="${1:-}"

cd_workflow=".github/workflows/cd.yaml"
publish_workflow=".github/workflows/⚡reusable-publish.yaml"
publish_script="scripts/ci/publish.sh"

case "${mode}" in
tag)
  [ ! -f "${cd_workflow}" ] && echo "❌ '${cd_workflow}' is missing" >&2 && exit 1
  ! yq -o=json "${cd_workflow}" | jq -e '.on.push.tags | contains(["v*.*.*"])' >/dev/null && echo "❌ CD must trigger on the release tag pattern 'v*.*.*'" >&2 && exit 1
  echo "✅ publish tag policy conforms"
  ;;
credential)
  [ ! -f "${publish_workflow}" ] && echo "❌ '${publish_workflow}' is missing" >&2 && exit 1
  ! yq -o=json "${publish_workflow}" | jq -e '.on.workflow_call.secrets.NPM_API_KEY.required == true' >/dev/null && echo "❌ reusable publish workflow must declare the NPM_API_KEY secret as required" >&2 && exit 1
  ! rg -qF 'NPM_API_KEY: ${{ secrets.NPM_API_KEY }}' "${publish_workflow}" && echo "❌ reusable publish workflow must forward NPM_API_KEY into the publish step env" >&2 && exit 1
  ! rg -qF 'NPM_API_KEY' "${publish_script}" && echo "❌ '${publish_script}' must consume NPM_API_KEY" >&2 && exit 1
  echo "✅ publish credential policy conforms"
  ;;
command)
  [ ! -f "${publish_script}" ] && echo "❌ '${publish_script}' is missing" >&2 && exit 1
  ! rg -qF -- '--access public' "${publish_script}" && echo "❌ '${publish_script}' must publish with --access public" >&2 && exit 1
  ! rg -qF -- '--tolerate-republish' "${publish_script}" && echo "❌ '${publish_script}' must publish with --tolerate-republish" >&2 && exit 1
  echo "✅ publish command policy conforms"
  ;;
*)
  echo "❌ mode must be 'tag', 'credential', or 'command'" >&2
  exit 1
  ;;
esac
