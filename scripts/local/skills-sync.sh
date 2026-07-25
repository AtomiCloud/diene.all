#!/usr/bin/env bash
set -euo pipefail

vendor_dir=".claude/skills/vendor"
staging="$(mktemp -d .claude/skills/.vendor.XXXXXX)"
trap 'chmod -R u+w "${staging}" 2>/dev/null || true; rm -rf "${staging}"' EXIT

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

if [ -f go.mod ] && command -v go >/dev/null 2>&1; then
  # A fresh CI runner has no populated module cache yet. Download first so
  # `go list -m` reports dependency directories instead of silently producing
  # an empty skills staging tree.
  go mod download
  while IFS=$'\t' read -r module module_dir; do
    [ -n "${module_dir}" ] || continue
    skills_dir="${module_dir}/skills"
    [ -d "${skills_dir}" ] || continue
    package="$(basename "${module}")"
    mkdir -p "${staging}/${package}"
    cp -R "${skills_dir}/." "${staging}/${package}/"
  done < <(go list -m -json all | jq -r 'select(.Main != true) | select(.Path | test("(^|/)diene[._-]")) | [.Path, .Dir] | @tsv')
elif [ -f go.mod ] && [ -d "${vendor_dir}" ]; then
  # The generated pre-commit validator runtime intentionally has a minimal PATH
  # without Go. Preserve the already-synchronized Go skills there; CI setup and
  # direct validation run this script with Go available and perform the real sync.
  for package_dir in "${vendor_dir}"/diene.go-*; do
    [ -d "${package_dir}" ] || continue
    package="$(basename "${package_dir}")"
    mkdir -p "${staging}/${package}"
    cp -R "${package_dir}/." "${staging}/${package}/"
  done
  echo "⚠️ Go unavailable; preserved existing vendored Go skills" >&2
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

chmod -R u+w "${staging}"
if [ -d "${vendor_dir}" ]; then
  chmod -R u+w "${vendor_dir}"
fi
rm -rf "${vendor_dir}"
mkdir -p "$(dirname "${vendor_dir}")"
mv "${staging}" "${vendor_dir}"
trap - EXIT

echo "✅ Vendored skills synchronized"
