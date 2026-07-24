#!/usr/bin/env bash
# Vendored, checksum-pinned Gateway API standard-channel CRD fixture for the
# platinum k3d integration proof (RB-244 repair).
#
# The proof previously fetched the standard channel live from a frozen upstream
# release URL. Upstream renamed the standard-channel.yaml asset to
# standard-install.yaml, so the frozen URL began returning HTTP 404 and the
# proof went terminal red. The fixture is now vendored verbatim from the
# authoritative upstream release and applied only after a fail-closed SHA-256
# check, so the proof no longer depends on a live, renameable external resource.
#
# Version pin (corrected 2026-07-24): kgateway v2.2.9 supports only Gateway API
# 1.2, 1.3, and 1.4 — installing the v1.6.0 standard channel made the kgateway
# controller abort at startup ("unsupported Gateway API version") and crashloop,
# so the Gateway never reached Programmed and the k3d proof failed. Pinned to
# v1.4.0, the newest channel kgateway v2.2.9 accepts.
#
# Usage:
#   gateway-api-crd-fixture.sh verify    fail-closed verify; prints abs path
#   gateway-api-crd-fixture.sh path      prints the absolute fixture path
#   gateway-api-crd-fixture.sh version   prints the pinned upstream version
#   gateway-api-crd-fixture.sh sha256    prints the pinned SHA-256
#   gateway-api-crd-fixture.sh describe  prints the full provenance
set -euo pipefail

# Pinned upstream version (Gateway API standard channel). Must stay within the
# kgateway-supported range (1.2-1.4 for kgateway v2.2.9); see the version-pin
# note above.
GATEWAY_API_CRD_VERSION="v1.4.0"
# Fixture path relative to the repository root; verbatim upstream bytes.
GATEWAY_API_CRD_FIXTURE_REL="tests/fixtures/gateway-api-standard-channel-v1.4.0.yaml"
# SHA-256 of the vendored fixture (fail-closed pin). Stored with a "sha256:"
# prefix, matching Chart.lock digest notation; the prefix is stripped before
# comparison (sha256sum emits bare hex).
GATEWAY_API_CRD_FIXTURE_SHA256="sha256:6a4029e661446d64add866a00ecdc40c14219b68777ab614c5cdaac0adb481f1"
# Authoritative upstream source the bytes were vendored from (provenance only;
# the proof never fetches this at run time).
GATEWAY_API_CRD_SOURCE_URL="https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml"

# Resolve the repository root from this file's location (scripts/local/ -> root)
# so the verifier is correct regardless of the caller's working directory.
_gateway_api_crd_fixture_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local root_dir
  root_dir="$(cd "${script_dir}/../.." && pwd)"
  printf '%s\n' "${root_dir}"
}

# Print the absolute path of the vendored fixture.
_gateway_api_crd_fixture_path() {
  printf '%s/%s\n' "$(_gateway_api_crd_fixture_root)" "${GATEWAY_API_CRD_FIXTURE_REL}"
}

# Verify the fixture exists, is non-empty, and hashes to the pinned SHA-256.
# Fail-closed: any failure prints a diagnostic and returns non-zero. On success,
# prints the absolute fixture path.
_gateway_api_crd_fixture_verify() {
  local fixture_path expected_sha actual_sha
  fixture_path="$(_gateway_api_crd_fixture_path)"
  expected_sha="${GATEWAY_API_CRD_FIXTURE_SHA256#sha256:}"
  if [ ! -e "${fixture_path}" ]; then
    echo "❌ Gateway API CRD fixture missing: ${fixture_path}" >&2
    return 1
  fi
  if [ ! -s "${fixture_path}" ]; then
    echo "❌ Gateway API CRD fixture is empty: ${fixture_path}" >&2
    return 1
  fi
  actual_sha="$(sha256sum "${fixture_path}" | cut -d ' ' -f1)"
  if [ "${actual_sha}" != "${expected_sha}" ]; then
    echo "❌ Gateway API CRD fixture checksum mismatch" >&2
    echo "    expected ${expected_sha}" >&2
    echo "    actual   ${actual_sha}" >&2
    echo "    path     ${fixture_path}" >&2
    return 1
  fi
  printf '%s\n' "${fixture_path}"
}

# Print the pinned provenance (version, authoritative source, SHA-256, path).
_gateway_api_crd_fixture_describe() {
  printf 'Gateway API standard-channel CRD fixture\n'
  printf '  version:     %s\n' "${GATEWAY_API_CRD_VERSION}"
  printf '  source url:  %s\n' "${GATEWAY_API_CRD_SOURCE_URL}"
  printf '  sha256:      %s\n' "${GATEWAY_API_CRD_FIXTURE_SHA256#sha256:}"
  printf '  fixture:     %s\n' "$(_gateway_api_crd_fixture_path)"
}

case "${1:-verify}" in
verify)
  _gateway_api_crd_fixture_verify
  ;;
path)
  _gateway_api_crd_fixture_path
  ;;
version)
  printf '%s\n' "${GATEWAY_API_CRD_VERSION}"
  ;;
sha256)
  printf '%s\n' "${GATEWAY_API_CRD_FIXTURE_SHA256#sha256:}"
  ;;
describe)
  _gateway_api_crd_fixture_describe
  ;;
*)
  echo "usage: ${0} {verify|path|version|sha256|describe}" >&2
  exit 2
  ;;
esac
