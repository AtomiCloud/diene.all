#!/usr/bin/env bash
set -euo pipefail

version="${1:?release version required}"
[[ $version =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
  echo "❌ version '$version' must match X.Y.Z" >&2
  exit 1
}

sed -i -E "s/^version: .*/version: $version/" pubspec.yaml
printf '%s\n' "$version" >VERSION
