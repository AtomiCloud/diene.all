#!/usr/bin/env bash
set -euo pipefail

# Manifest==tag publish guard (R10/M1-M3): the published version is stamped at
# the release commit and NEVER mutated by the publish step — publish only
# VERIFIES that pubspec.yaml `version`, the VERSION file, and (when given) the
# release tag all agree. Exits 1 on any mismatch.
#
#   manifest-tag.sh check            # pubspec == VERSION
#   manifest-tag.sh check vX.Y.Z     # pubspec == VERSION == tag
#   manifest-tag.sh selftest         # negative-path drill: proves it exits 1

mode="${1:-check}"

check() {
  local tag="${1:-}"
  local pubspec_version file_version
  pubspec_version="$(yq -r '.version' pubspec.yaml)"
  file_version="$(cat VERSION)"

  if [ "${pubspec_version}" != "${file_version}" ]; then
    echo "❌ pubspec.yaml version (${pubspec_version}) != VERSION (${file_version})" >&2
    return 1
  fi
  if [ -n "${tag}" ] && [ "${tag#v}" != "${pubspec_version}" ]; then
    echo "❌ tag (${tag#v}) != manifest version (${pubspec_version})" >&2
    return 1
  fi
  echo "✅ manifest==tag: ${pubspec_version}"
  return 0
}

case "${mode}" in
check)
  check "${2:-}"
  ;;
selftest)
  # Prove the guard is real: a deliberate local mismatch MUST exit 1, and a
  # matching pair MUST pass. Runs entirely in a temp fixture — no repo mutation.
  fixture="$(mktemp -d)"
  trap 'rm -rf "${fixture}"' EXIT
  cp pubspec.yaml VERSION "${fixture}/"
  cp scripts/validate/manifest-tag.sh "${fixture}/"
  cd "${fixture}"
  printf '9.9.9\n' >VERSION
  sed -i -E 's/^version: .*/version: 1.2.3/' pubspec.yaml
  if bash manifest-tag.sh check 2>/dev/null; then
    echo "❌ selftest: guard did NOT catch a mismatch" >&2
    exit 1
  fi
  printf '1.2.3\n' >VERSION
  bash manifest-tag.sh check >/dev/null || {
    echo "❌ selftest: guard rejected a matching pair" >&2
    exit 1
  }
  echo "✅ manifest guard selftest: catches mismatch, passes on match"
  ;;
*)
  echo "❌ unsupported mode '${mode}' (check|selftest)" >&2
  exit 1
  ;;
esac
