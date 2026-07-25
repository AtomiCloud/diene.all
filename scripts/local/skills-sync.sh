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

if [ -f go.mod ]; then
  # The restricted pre-commit hook PATH omits go; honor DIENE_SKILLS_GO (an
  # absolute go path exported by the dev shell / scripts/ci/pre-commit.sh) and
  # fall back to PATH.
  skills_go="${DIENE_SKILLS_GO:-$(command -v go 2>/dev/null || true)}"
  if [ -x "${skills_go}" ]; then
    # Capture enumeration OUTSIDE process substitution so a go/jq failure aborts
    # before the vendor tree is replaced (pipefail surfaces either failure).
    go_skill_modules="$("${skills_go}" list -m -json all | jq -r 'select(.Path | test("(^|/)diene[._-]")) | [.Path, .Dir] | @tsv')" || {
      echo "❌ skills-sync: enumerating dependency skills failed" >&2
      exit 1
    }
    while IFS=$'\t' read -r module module_dir; do
      [ -n "${module_dir}" ] || continue
      skills_dir="${module_dir}/skills"
      [ -d "${skills_dir}" ] || continue
      package="$(basename "${module}")"
      mkdir -p "${staging}/${package}"
      cp -R "${skills_dir}/." "${staging}/${package}/"
    done <<<"${go_skill_modules}"
  elif [ -d "${vendor_dir}" ] && find "${vendor_dir}" -mindepth 1 ! -name .gitkeep -print -quit | grep -q .; then
    # Go is unavailable but the committed vendor tree already carries real skill
    # content. Refuse to replace a complete tree with an un-enumerable (and thus
    # incomplete) one — fail closed instead of vendoring a partial set.
    echo "❌ skills-sync: go is required to re-enumerate dependency skills; set DIENE_SKILLS_GO to an absolute go path" >&2
    exit 1
  else
    # Go is unavailable and the committed vendor tree is already empty (the flake's
    # own offline check runs hooks under a restricted PATH with no go). There is no
    # complete tree to wipe, so skip go enumeration loudly rather than fail: the
    # replacement below reproduces the identical empty tree.
    echo "⚠️  skills-sync: go unavailable and vendor tree already empty; skipping go dependency enumeration" >&2
  fi
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

# Dependency skills are copied from read-only module caches, so the previous
# vendor tree can be read-only; make it writable before replacing it.
[ -d "${vendor_dir}" ] && chmod -R u+w "${vendor_dir}"
rm -rf "${vendor_dir}"
mkdir -p "$(dirname "${vendor_dir}")"
mv "${staging}" "${vendor_dir}"
trap - EXIT

echo "✅ Vendored skills synchronized"
