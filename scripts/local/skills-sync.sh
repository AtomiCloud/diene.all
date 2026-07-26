#!/usr/bin/env bash
set -euo pipefail

# skills-sync regenerates the committed dependency-skill tree under
# .claude/skills/vendor/<package>/ from the installed dependencies of every
# ecosystem this repo uses. It is a REGENERATOR: it always rebuilds the tree from
# the resolved dependencies, so it requires the toolchain that enumerates them.
# The vendored tree carries DEPENDENCY skills only; a module never vendors its
# own skills, so the Go main module is excluded.

vendor_dir=".claude/skills/vendor"

# A Go module must be able to enumerate its dependency skills BEFORE anything is
# staged. Resolve Go up front and fail closed when it is missing or the
# enumeration fails, so a restricted environment can never produce a partial
# (Node/.NET/Dart-only) tree for a Go module. The restricted pre-commit hook PATH
# omits go, so honor DIENE_SKILLS_GO (an absolute go path exported by the dev
# shell / scripts/ci/pre-commit.sh) before falling back to PATH.
go_skill_modules=""
if [ -f go.mod ]; then
  skills_go="${DIENE_SKILLS_GO:-$(command -v go 2>/dev/null || true)}"
  if [ ! -x "${skills_go}" ]; then
    echo "❌ skills-sync: Go is required to enumerate dependency skills for a Go module; set DIENE_SKILLS_GO to an absolute go path" >&2
    exit 1
  fi
  # Exclude the main module (.Main) so the repo does not self-vendor its own
  # skills. Capture the enumeration here so a go/jq failure aborts before staging.
  go_skill_modules="$("${skills_go}" list -m -json all | jq -r 'select((.Path | test("(^|/)diene[._-]")) and (.Main != true)) | [.Path, .Dir] | @tsv')" || {
    echo "❌ skills-sync: enumerating Go dependency skills failed" >&2
    exit 1
  }
fi

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
    # An empty line means the module has no Diene dependency skills at all.
    [ -n "${module}" ] || continue
    # A resolved dependency with no module directory or no skills directory is
    # partial input: fail BEFORE the replacement rather than vendor a subset.
    if [ -z "${module_dir}" ] || [ ! -d "${module_dir}" ]; then
      echo "❌ skills-sync: dependency ${module} has no resolved module directory" >&2
      exit 1
    fi
    skills_dir="${module_dir}/skills"
    if [ ! -d "${skills_dir}" ]; then
      echo "❌ skills-sync: dependency ${module} has no skills directory" >&2
      exit 1
    fi
    package="$(basename "${module}")"
    mkdir -p "${staging}/${package}"
    cp -R "${skills_dir}/." "${staging}/${package}/"
  done <<<"${go_skill_modules}"
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

# Dependency skills are copied from read-only module caches, so both the previous
# vendor tree and the staged copies can be read-only; make them writable before
# replacing the tree in one move.
[ -d "${vendor_dir}" ] && chmod -R u+w "${vendor_dir}"
chmod -R u+w "${staging}"
rm -rf "${vendor_dir}"
mkdir -p "$(dirname "${vendor_dir}")"
mv "${staging}" "${vendor_dir}"
trap - EXIT

echo "✅ Vendored skills synchronized"
