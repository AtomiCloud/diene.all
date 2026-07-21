#!/usr/bin/env bash
set -euo pipefail

# Verifies the IANA timezone allowlist is reproducible from the vendored,
# digest-pinned official source — never from host `/usr/share/zoneinfo`.
#
#   1. every vendored native file matches its recorded SHA-256 (SHA256SUMS);
#   2. `lib/src/iana_zones.dart` byte-matches regeneration from that source.

source_dir="${1:-third_party/iana-tzdata-2026b}"

if [ ! -d "${source_dir}" ]; then
  echo "❌ vendored IANA source not found: ${source_dir}" >&2
  exit 1
fi

echo "→ verifying vendored source digests in ${source_dir}"
(cd "${source_dir}" && sha256sum -c SHA256SUMS)

echo "→ verifying lib/src/iana_zones.dart matches the vendored source"
dart run tool/gen_iana_zones.dart --source "${source_dir}" --check

echo "✅ IANA allowlist reproducible from pinned source ${source_dir}"
