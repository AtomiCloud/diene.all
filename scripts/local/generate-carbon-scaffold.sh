#!/usr/bin/env bash
set -euo pipefail

output="${1:-templates/base}"
[ "${output#/}" = "${output}" ] || {
  echo "❌ scaffold output must be repository-relative" >&2
  exit 1
}

mkdir -p "${output}"
find "${output}" -mindepth 1 -delete
mkdir -p "${output}/chart" "${output}/primordial-chart"
cp -R chart/. "${output}/chart/"
cp -R primordial-chart/. "${output}/primordial-chart/"
cp platform.yaml platform.schema.json "${output}/"

while IFS= read -r file; do
  sed -i 's/diene/let__platform__/g' "${file}"
done < <(rg -l 'diene' "${output}" || true)

echo "✅ Carbon platform-name-only scaffold generated at ${output}"
