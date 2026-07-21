#!/usr/bin/env bash
set -euo pipefail

manifest_version="$(awk '$1 == "version:" { print $2; exit }' pubspec.yaml)"
version_file="$(tr -d '\n' <VERSION)"
semver='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'

[[ $manifest_version =~ ^$semver$ ]] || {
  echo "❌ pubspec version '$manifest_version' must match X.Y.Z" >&2
  exit 1
}
[[ $version_file =~ ^$semver$ ]] || {
  echo "❌ VERSION '$version_file' must match X.Y.Z" >&2
  exit 1
}
[ "$manifest_version" = "$version_file" ] || {
  echo "❌ pubspec version $manifest_version does not match VERSION $version_file" >&2
  exit 1
}

tag="${1:-}"
if [ -n "$tag" ]; then
  [[ $tag =~ ^v$semver$ ]] || {
    echo "❌ release tag '$tag' must match vX.Y.Z" >&2
    exit 1
  }
  release_version="${tag#v}"
  [ "$manifest_version" = "$release_version" ] || {
    echo "❌ pubspec version $manifest_version does not match tag $tag" >&2
    exit 1
  }
  echo "✅ manifest and VERSION match $tag"
  exit 0
fi

echo "✅ pubspec version and VERSION match $manifest_version"
