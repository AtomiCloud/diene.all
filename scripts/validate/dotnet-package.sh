#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
artifacts="${2:-artifacts/package}"
version="${3:-$(xmlstarlet sel -t -v '/Project/PropertyGroup/Version' Version.props)}"

[ "${mode}" != "inventory" ] && [ "${mode}" != "metadata" ] && [ "${mode}" != "symbols" ] && echo "❌ Usage: dotnet-package.sh <inventory|metadata|symbols> [artifacts] [version]" >&2 && exit 1
[ ! -d "${artifacts}" ] && echo "❌ Package artifact directory '${artifacts}' not found" >&2 && exit 1

package_ids=(AtomiCloud.Diene.Note AtomiCloud.Diene.Note.TestHelper)

if [ "${mode}" = "inventory" ]; then
  for package_id in "${package_ids[@]}"; do
    [ ! -f "${artifacts}/${package_id}.${version}.nupkg" ] && echo "❌ Missing ${package_id}.${version}.nupkg" >&2 && exit 1
    [ ! -f "${artifacts}/${package_id}.${version}.snupkg" ] && echo "❌ Missing ${package_id}.${version}.snupkg" >&2 && exit 1
  done
  [ "$(find "${artifacts}" -maxdepth 1 -type f \( -name '*.nupkg' -o -name '*.snupkg' \) | wc -l)" -ne 4 ] && echo "❌ Package inventory must contain exactly four artifacts" >&2 && exit 1
  echo "✅ Dual-package artifact inventory is complete at ${version}"
  exit 0
fi

if [ "${mode}" = "metadata" ]; then
  for package_id in "${package_ids[@]}"; do
    package="${artifacts}/${package_id}.${version}.nupkg"
    nuspec="$(mktemp)"
    trap 'rm -f "${nuspec}"' EXIT
    unzip -p "${package}" "${package_id}.nuspec" >"${nuspec}"
    namespace="$(xmlstarlet sel -t -v 'namespace-uri(/*)' "${nuspec}")"
    [ "$(xmlstarlet sel -N n="${namespace}" -t -v '/n:package/n:metadata/n:id' "${nuspec}")" != "${package_id}" ] && echo "❌ ${package_id} metadata id mismatch" >&2 && exit 1
    [ "$(xmlstarlet sel -N n="${namespace}" -t -v '/n:package/n:metadata/n:version' "${nuspec}")" != "${version}" ] && echo "❌ ${package_id} metadata version mismatch" >&2 && exit 1
    [ "$(xmlstarlet sel -N n="${namespace}" -t -v '/n:package/n:metadata/n:authors' "${nuspec}")" != "AtomiCloud" ] && echo "❌ ${package_id} authors metadata missing" >&2 && exit 1
    [ "$(xmlstarlet sel -N n="${namespace}" -t -v '/n:package/n:metadata/n:license[@type="expression"]' "${nuspec}")" != "MIT" ] && echo "❌ ${package_id} SPDX license metadata missing" >&2 && exit 1
    [ "$(xmlstarlet sel -N n="${namespace}" -t -v '/n:package/n:metadata/n:readme' "${nuspec}")" != "README.md" ] && echo "❌ ${package_id} package README metadata missing" >&2 && exit 1
    [ "$(xmlstarlet sel -N n="${namespace}" -t -v '/n:package/n:metadata/n:icon' "${nuspec}")" != "logo.png" ] && echo "❌ ${package_id} package icon metadata missing" >&2 && exit 1
    [ -z "$(xmlstarlet sel -N n="${namespace}" -t -v '/n:package/n:metadata/n:description' "${nuspec}")" ] && echo "❌ ${package_id} description metadata missing" >&2 && exit 1
    [ "$(xmlstarlet sel -N n="${namespace}" -t -v '/n:package/n:metadata/n:projectUrl' "${nuspec}")" != "https://github.com/AtomiCloud/diene.dotnet-lib" ] && echo "❌ ${package_id} project URL metadata missing" >&2 && exit 1
    [ "$(xmlstarlet sel -N n="${namespace}" -t -v '/n:package/n:metadata/n:repository/@url' "${nuspec}")" != "https://github.com/AtomiCloud/diene.dotnet-lib" ] && echo "❌ ${package_id} repository metadata missing" >&2 && exit 1
    contents="$(unzip -Z1 "${package}")"
    for required in README.md logo.png LICENSE skills/diene-dotnet-note-usage/SKILL.md; do
      ! echo "${contents}" | rg -Fxq "${required}" && echo "❌ ${package_id} package is missing ${required}" >&2 && exit 1
    done
    rm -f "${nuspec}"
    trap - EXIT
  done
  echo "✅ Package metadata and embedded assets are complete"
  exit 0
fi

for package_id in "${package_ids[@]}"; do
  package="${artifacts}/${package_id}.${version}.snupkg"
  contents="$(unzip -Z1 "${package}")"
  ! echo "${contents}" | rg -q '^lib/net10[.]0/.+[.]pdb$' && echo "❌ ${package_id} symbols package contains no portable PDB" >&2 && exit 1
  ! echo "${contents}" | rg -Fxq "${package_id}.nuspec" && echo "❌ ${package_id} symbols package contains no nuspec" >&2 && exit 1
done

echo "✅ Symbol package contents are complete"
