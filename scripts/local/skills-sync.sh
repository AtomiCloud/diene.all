#!/usr/bin/env bash
set -euo pipefail

vendor_dir=".claude/skills/vendor"

# The vendored copies come FROM installed packages; without node_modules the
# sync would stage an empty tree and delete every committed skill. Fail loudly
# instead — the caller forgot to install first.
if [ ! -d node_modules/@atomicloud ]; then
  echo "❌ node_modules/@atomicloud missing — run bun install before skills-sync" >&2
  exit 1
fi

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

# Vendored assets are plain files; the staging copy inherits whatever modes
# the package manager gave node_modules (bun marks some files executable on
# some machines), so modes are normalized before comparing — otherwise a
# mode-only difference forces a replace and the freshness hook reads the mode
# flip as a modification.
find "${staging}" -type f -exec chmod 644 {} +

# Idempotent swap: leave the tree untouched when nothing changed, so a
# freshness re-run inside pre-commit never churns mtimes on a clean checkout
# (CI treats any file modification by a hook as a failure). The comparison
# uses git rather than diffutils — the pre-commit validator runtime carries
# git but no diff binary, and a missing binary must not degrade into the
# replace branch.
if [ -d "${vendor_dir}" ] && git diff --no-index --quiet "${staging}" "${vendor_dir}" 2>/dev/null; then
  rm -rf "${staging}"
else
  rm -rf "${vendor_dir}"
  mkdir -p "$(dirname "${vendor_dir}")"
  mv "${staging}" "${vendor_dir}"
fi
trap - EXIT

echo "✅ Vendored skills synchronized"
