#!/usr/bin/env bash
set -euo pipefail

fetch_signing_files() {
  local landscape="${1:?landscape is required}" targets target_id
  targets="$(./scripts/ci/ios-signing-targets.sh "${landscape}")"
  while IFS= read -r target_id; do
    app-store-connect fetch-signing-files "${target_id}" \
      --type IOS_APP_STORE \
      --certificate-key @env:CERTIFICATE_PRIVATE_KEY \
      --create
  done <<<"${targets}"
  ./scripts/ci/doctor-ios.sh "${landscape}"
}

next_build_number() {
  local latest="${1:-0}" run_number="${2:-0}" next
  next="$((latest + 1))"
  [ "${run_number}" -gt "${next}" ] && next="${run_number}"
  printf '%s\n' "${next}"
}

build_number_for() {
  local landscape="${1:?landscape is required}" apple_id latest
  apple_id="$(yq ".landscapes[] | select(.name == \"${landscape}\") | .apple_id // \"\"" lpsm.yaml)"
  latest=0
  [ -n "${apple_id}" ] && latest="$(app-store-connect get-latest-build-number "${apple_id}" || echo 0)"
  next_build_number "${latest:-0}" "${GITHUB_RUN_NUMBER:-0}"
}

release_version_name() {
  if [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then
    printf '%s\n' "${GITHUB_REF_NAME#v}"
  else
    yq -r '.version' pubspec.yaml | cut -d+ -f1
  fi
}
