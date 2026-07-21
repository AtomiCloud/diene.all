#!/usr/bin/env bash
set -euo pipefail

# Proves the release version discipline for the Dart library, host-safely and
# without publishing:
#   POSITIVE — bump.sh stamps VERSION and pubspec.yaml to a plain semver, and
#              pubspec.yaml is registered as a release asset.
#   NEGATIVE — verify-manifest.sh (the manifest==tag guard) EXITS 1 when the
#              manifest drifts from the tag, and passes when it matches.

root="$(pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture}"' EXIT
cp pubspec.yaml VERSION "${fixture}/"

# POSITIVE: stamping produces plain semver (no +build suffix).
(cd "${fixture}" && bash "${root}/scripts/release/bump.sh" v9.8.7)
[ "$(cat "${fixture}/VERSION")" != '9.8.7' ] && echo "❌ VERSION was not stamped" >&2 && exit 1
[ "$(yq '.version' "${fixture}/pubspec.yaml")" != '9.8.7' ] && echo "❌ pubspec.yaml was not stamped to plain semver" >&2 && exit 1
rg -q 'pubspec.yaml' atomi_release.yaml || {
  echo "❌ pubspec.yaml is absent from release assets" >&2
  exit 1
}

# NEGATIVE: manifest==tag guard rejects a mismatched tag.
if (cd "${fixture}" && bash "${root}/scripts/release/verify-manifest.sh" v1.0.0) >/dev/null 2>&1; then
  echo "❌ verify-manifest.sh accepted a mismatched tag" >&2
  exit 1
fi
# POSITIVE: guard passes when manifest==tag.
(cd "${fixture}" && bash "${root}/scripts/release/verify-manifest.sh" v9.8.7) >/dev/null

echo "✅ release stamping is plain semver and the manifest==tag guard fails closed"
