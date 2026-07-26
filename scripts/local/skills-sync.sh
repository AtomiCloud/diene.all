#!/usr/bin/env bash
set -euo pipefail

# ### INTERIM — OWNED BY workspace, SUPERSEDED BY THE PARENT MERGE
# #### source: workspace · interim applied on go-consumer · owner session: tim
#     (ms2f8932-ce4cf7e3, node-worker:workspace-releaser)
#
# Package caches are READ-ONLY: the Go module cache stores files 0444 and
# directories 0555, and the NuGet and pub caches do the same. `cp -R` preserves
# those modes, so the staging tree and the previous vendor tree cannot be
# removed and this script exits non-zero — which fails scripts/ci/setup.sh and
# therefore every CI job. Only bun's node_modules is writable, which is why the
# bun line never hit this.
#
# The durable fix belongs at workspace and arrives by cascade. This is an
# R-E8a LATENCY-CLAUSE interim, NOT an independent per-branch port: when the
# parent merge reaches this branch, resolve IN FAVOUR OF THE PARENT and DELETE
# this block rather than merging around it. Recorded as a parent obligation in
# exec/nodes/go-consumer/node.json.
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

# INTERIM (see the header block): make the copies writable before any removal,
# because they inherit read-only modes from the source package cache.
chmod -R u+w "${staging}"
[ -d "${vendor_dir}" ] && chmod -R u+w "${vendor_dir}"
rm -rf "${vendor_dir}"
mkdir -p "$(dirname "${vendor_dir}")"
mv "${staging}" "${vendor_dir}"
trap - EXIT

echo "✅ Vendored skills synchronized"
