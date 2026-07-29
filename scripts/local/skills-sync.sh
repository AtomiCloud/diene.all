#!/usr/bin/env bash
set -euo pipefail

# ### workspace
# #### source: workspace
vendor_dir=".claude/skills/vendor"
staging="$(mktemp -d .claude/skills/.vendor.XXXXXX)"
trap 'rm -rf "${staging}"' EXIT
declared_dependency=false
resolved_dependency=false

touch "${staging}/.gitkeep"

if [ -f package.json ]; then
  jq empty package.json
  if jq -e '
      [
        (.dependencies // {}),
        (.devDependencies // {}),
        (.optionalDependencies // {}),
        (.peerDependencies // {})
      ]
      | add
      | keys[]
      | select(startswith("@atomicloud/diene."))
    ' package.json >/dev/null; then
    declared_dependency=true
  fi
fi

if [ -f bun.lock ] && rg -q '^[[:space:]]*"@atomicloud/diene\.' bun.lock; then
  declared_dependency=true
fi

for package_dir in node_modules/@atomicloud/diene.*; do
  [ -d "${package_dir}" ] || continue
  resolved_dependency=true
  package="$(basename "${package_dir}")"
  skills_dir="${package_dir}/skills"
  [ -d "${skills_dir}" ] || continue
  mkdir -p "${staging}/${package}"
  cp -R "${skills_dir}/." "${staging}/${package}/"
done

if [ -f Directory.Packages.props ]; then
  while IFS=$'\t' read -r package version; do
    [ -n "${package}" ] || continue
    declared_dependency=true
    cache_id="$(echo "${package}" | tr '[:upper:]' '[:lower:]')"
    package_dir="${HOME}/.nuget/packages/${cache_id}/${version}"
    [ -d "${package_dir}" ] || continue
    resolved_dependency=true
    skills_dir="${package_dir}/skills"
    [ -d "${skills_dir}" ] || continue
    mkdir -p "${staging}/${package}"
    cp -R "${skills_dir}/." "${staging}/${package}/"
  done < <(rg -o 'PackageVersion Include="AtomiCloud\.Diene\.[^"]+" Version="[^"]+"' Directory.Packages.props | sed -E 's/PackageVersion Include="([^"]+)" Version="([^"]+)"/\1\t\2/')
fi

if [ -f go.mod ]; then
  go_manifest="$(go mod edit -json)"
  go_declares_external=false
  if jq -e 'any(.Require[]?; .Path | test("(^|/)diene[._-]"))' <<<"${go_manifest}" >/dev/null; then
    declared_dependency=true
    go_declares_external=true
  fi
  if jq -e '(.Module.Path // "") | test("(^|/)diene[._-]")' <<<"${go_manifest}" >/dev/null; then
    declared_dependency=true
  fi

  while IFS=$'\t' read -r module module_dir main_module; do
    [ -n "${module_dir}" ] || continue
    if [ "${main_module}" = false ] || [ "${go_declares_external}" = false ]; then
      resolved_dependency=true
    fi
    skills_dir="${module_dir}/skills"
    [ -d "${skills_dir}" ] || continue
    package="$(basename "${module}")"
    mkdir -p "${staging}/${package}"
    cp -R "${skills_dir}/." "${staging}/${package}/"
  done < <(go list -m -json all | jq -r 'select(.Path | test("(^|/)diene[._-]")) | [.Path, .Dir, (.Main // false)] | @tsv')
fi

if rg -q '^(name:[[:space:]]+diene_[[:alnum:]_]+|[[:space:]]+diene_[[:alnum:]_]+[[:space:]]*:)' --glob pubspec.yaml --glob pubspec.lock .; then
  declared_dependency=true
fi

if [ -f .dart_tool/package_config.json ]; then
  jq empty .dart_tool/package_config.json
  while IFS=$'\t' read -r package root_uri; do
    package_root="$(realpath -m ".dart_tool/${root_uri}")"
    [ -d "${package_root}" ] || continue
    resolved_dependency=true
    skills_dir="${package_root}/skills"
    [ -d "${skills_dir}" ] || continue
    mkdir -p "${staging}/${package}"
    cp -R "${skills_dir}/." "${staging}/${package}/"
  done < <(jq -r '.packages[] | select(.name | startswith("diene_")) | [.name, .rootUri] | @tsv' .dart_tool/package_config.json)
fi

# ### bun-consumer-skills-sync-guard
# #### source: bun-consumer
# DISCHARGED on this cascade — SUPERSEDED BY workspace-vendor-swap BELOW, not dropped.
# Recorded here, in the guard's own place, because an obligation that vanishes without
# a stated reason is indistinguishable from one quietly removed.
#
# The guard named its own retirement: "Upstream owns the real fix; this guard keeps the
# destructive swap honest." Upstream now has it, immediately below.
#
# UPSTREAM'S TRIGGER IS STRICTLY FINER, which is why keeping both is wrong:
#   this guard  — fired when the staging tree was empty FOR ANY REASON
#   workspace   — fires on declared_dependency && !resolved_dependency
# The former is a SUPERSET that cannot distinguish a cold checkout from a tree that
# legitimately declares nothing. Verified on THIS branch rather than inherited from the
# leaf ruling: both sides were read in full before choosing.
# ### workspace-vendor-swap
# #### source: workspace
# A declaration with zero resolved packages is a cold checkout, not a request
# to replace committed skills with an empty staging tree.
if [ "${declared_dependency}" = true ] && [ "${resolved_dependency}" = false ] && [ -d "${vendor_dir}" ] &&
  [ -n "$(find "${vendor_dir}" -mindepth 1 ! -name .gitkeep -print -quit)" ]; then
  echo "⏭️ Declared diene packages are not installed; keeping the committed vendored skills"
  exit 0
fi

rm -rf "${vendor_dir}"
mkdir -p "$(dirname "${vendor_dir}")"
mv "${staging}" "${vendor_dir}"
trap - EXIT

echo "✅ Vendored skills synchronized"
