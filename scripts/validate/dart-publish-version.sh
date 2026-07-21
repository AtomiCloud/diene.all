#!/usr/bin/env bash
set -euo pipefail

tag="${1:-${GITHUB_REF_NAME:-}}"
[ -n "$tag" ] || {
  echo "❌ release tag not set" >&2
  exit 1
}
[[ $tag =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
  echo "❌ release tag '$tag' must match vX.Y.Z" >&2
  exit 1
}

manifest_version="$(awk '$1 == "version:" { print $2; exit }' pubspec.yaml)"
release_version="${tag#v}"
[ "$manifest_version" = "$release_version" ] || {
  echo "❌ pubspec version $manifest_version does not match tag $tag" >&2
  exit 1
}
[ "$(tr -d '\n' <VERSION)" = "$release_version" ] || {
  echo "❌ VERSION does not match tag $tag" >&2
  exit 1
}

echo "✅ manifest and VERSION match $tag"
