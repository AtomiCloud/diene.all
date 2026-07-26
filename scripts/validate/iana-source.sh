#!/usr/bin/env bash
set -euo pipefail

# Verifies the IANA timezone allowlist is reproducible from the vendored,
# digest-pinned official release — never from host `/usr/share/zoneinfo`.
#
#   1. every vendored native file matches its recorded SHA-256 (SHA256SUMS);
#   2. packages/diene_core_utils/lib/src/iana_zones.dart byte-matches
#      regeneration from that source;
#   3. the release string agrees across the vendored source, the generated
#      allowlist, and the shared C0 temporal contract.
#
# The vendored release lives at the REPOSITORY root (not inside the package) so it
# never enters the published pub archive: it is a build input, not a runtime one.

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_core_utils"
source_dir="${1:-third_party/iana-tzdata-2026b}"

if [ ! -d "${source_dir}" ]; then
  echo "❌ vendored IANA source not found: ${source_dir}" >&2
  exit 1
fi

echo "→ verifying vendored source digests in ${source_dir}"
# Capture the checker's OWN exit code: piping it would report the pipe tail's
# status instead, and count the lines so an empty ledger cannot read as success.
sums_lines="$(grep -cE '^[0-9a-f]{64}  ' "${source_dir}/SHA256SUMS")"
if [ "${sums_lines}" -lt 11 ]; then
  echo "❌ SHA256SUMS lists only ${sums_lines} files; expected at least 11" >&2
  exit 1
fi
(cd "${source_dir}" && sha256sum -c SHA256SUMS)
echo "  ✓ ${sums_lines} vendored files verified against their recorded digests"

echo "→ verifying the release string is pinned consistently"
vendored_release="$(tr -d '[:space:]' <"${source_dir}/version")"
generated_release="$(sed -n "s/^const String ianaTimeZoneRelease = '\(.*\)';\$/\1/p" "${member_dir}/lib/src/iana_zones.dart")"
contract_release="$(sed -n "s/^    ianaRelease: '\(.*\)',\$/\1/p" "${member_dir}/lib/src/c0_temporal_contract.dart")"
echo "  vendored=${vendored_release} generated=${generated_release} contract=${contract_release}"
if [ -z "${vendored_release}" ] || [ -z "${generated_release}" ] || [ -z "${contract_release}" ]; then
  echo "❌ a release pin could not be read; refusing to judge on missing data" >&2
  exit 1
fi
if [ "${vendored_release}" != "${generated_release}" ] || [ "${vendored_release}" != "${contract_release}" ]; then
  echo "❌ IANA release pins disagree" >&2
  exit 1
fi

echo "→ verifying the generated allowlist matches the vendored source"
(cd "${member_dir}" && dart run tool/gen_iana_zones.dart --source "../../${source_dir}" --check)

echo "✅ IANA allowlist reproducible from pinned release ${vendored_release} (${source_dir})"
