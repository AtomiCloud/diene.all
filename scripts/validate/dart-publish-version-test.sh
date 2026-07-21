#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
guard="$root/scripts/validate/dart-publish-version.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

cp "$root/pubspec.yaml" "$fixture/pubspec.yaml"
cp "$root/VERSION" "$fixture/VERSION"

(
  cd "$fixture"
  bash "$guard"
)

(
  cd "$fixture"
  bash "$root/scripts/release/bump.sh" 9.8.7
  bash "$guard"
  bash "$guard" v9.8.7
)

printf '%s\n' '9.8.6' >"$fixture/VERSION"
if (
  cd "$fixture"
  bash "$guard"
); then
  echo "❌ mismatched manifest and VERSION unexpectedly passed" >&2
  exit 1
fi

printf '%s\n' '9.8.7' >"$fixture/VERSION"
if (
  cd "$fixture"
  bash "$guard" v9.8.6
); then
  echo "❌ mismatched release tag unexpectedly passed" >&2
  exit 1
fi

echo "✅ generic and tagged Dart version guards passed regression fixtures"
