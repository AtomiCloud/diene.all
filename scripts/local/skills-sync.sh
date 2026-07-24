#!/usr/bin/env bash
set -euo pipefail

vendor_dir=".claude/skills/vendor"
staging="$(mktemp -d .claude/skills/.vendor.XXXXXX)"
trap 'rm -rf "${staging}"' EXIT

touch "${staging}/.gitkeep"

for skills_dir in node_modules/@atomicloud/diene.*/skills; do
  [ -d "${skills_dir}" ] || continue
  package="$(basename "$(dirname "${skills_dir}")")"
  mkdir -p "${staging}/${package}"
  cp -R "${skills_dir}/." "${staging}/${package}/"
done

if [ -f Directory.Packages.props ]; then
  while IFS=$'\t' read -r package version; do
    [ -n "${package}" ] || continue
    cache_id="$(echo "${package}" | tr '[:upper:]' '[:lower:]')"
    skills_dir="${HOME}/.nuget/packages/${cache_id}/${version}/skills"
    [ -d "${skills_dir}" ] || continue
    mkdir -p "${staging}/${package}"
    cp -R "${skills_dir}/." "${staging}/${package}/"
  done < <(rg -o 'PackageVersion Include="AtomiCloud\.Diene\.[^"]+" Version="[^"]+"' Directory.Packages.props | sed -E 's/PackageVersion Include="([^"]+)" Version="([^"]+)"/\1\t\2/')
fi

if [ -f go.mod ]; then
  while IFS=$'\t' read -r module module_dir; do
    [ -n "${module_dir}" ] || continue
    skills_dir="${module_dir}/skills"
    [ -d "${skills_dir}" ] || continue
    package="$(basename "${module}")"
    mkdir -p "${staging}/${package}"
    cp -R "${skills_dir}/." "${staging}/${package}/"
  done < <(go list -m -json all | jq -r 'select(.Path | test("(^|/)diene[._-]")) | [.Path, .Dir] | @tsv')
fi

if [ -f .dart_tool/package_config.json ]; then
  while IFS=$'\t' read -r package root_uri; do
    package_root="$(realpath -m ".dart_tool/${root_uri}")"
    skills_dir="${package_root}/skills"
    [ -d "${skills_dir}" ] || continue
    mkdir -p "${staging}/${package}"
    cp -R "${skills_dir}/." "${staging}/${package}/"
  done < <(jq -r '.packages[] | select(.name | startswith("diene_")) | [.name, .rootUri] | @tsv' .dart_tool/package_config.json)
fi

rm -rf "${vendor_dir}"
mkdir -p "$(dirname "${vendor_dir}")"
mv "${staging}" "${vendor_dir}"
trap - EXIT

echo "✅ Vendored skills synchronized"
