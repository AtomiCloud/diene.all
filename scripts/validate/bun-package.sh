#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
archive="${2:-pkg.tgz}"
[ "${mode}" != "pack-content" ] && [ "${mode}" != "metadata" ] && [ "${mode}" != "publint" ] && [ "${mode}" != "attw" ] && [ "${mode}" != "readme" ] && echo "❌ Usage: bun-package.sh <pack-content|metadata|publint|attw|readme> [archive]" >&2 && exit 1

if [ "${mode}" = "readme" ]; then
  package_name="$(jq -r '.name' package.json)"
  description="$(jq -r '.description' package.json)"
  keywords="$(jq -r '.keywords | join(", ")' package.json)"
  repository="$(jq -r '.repository.url' package.json | sed -e 's#^git+##' -e 's#[.]git$##')"
  [ -z "${description}" ] || [ "${description}" = "null" ] && echo "❌ package description is missing" >&2 && exit 1
  [ "$(jq '.keywords | length' package.json)" -lt 1 ] && echo "❌ package keywords are missing" >&2 && exit 1
  ! rg -F "${package_name}" README.md >/dev/null && echo "❌ README does not render the package name" >&2 && exit 1
  ! rg -F "Package description: ${description}" README.md >/dev/null && echo "❌ README does not render the package description" >&2 && exit 1
  ! rg -F "Package keywords: ${keywords}" README.md >/dev/null && echo "❌ README does not render the package keywords" >&2 && exit 1
  ! rg -F "${repository}/actions/workflows/ci.yaml/badge.svg" README.md >/dev/null && echo "❌ README CI badge does not render the repository URL" >&2 && exit 1
  ! rg -F "https://img.shields.io/npm/v/${package_name}" README.md >/dev/null && echo "❌ README npm badge does not render the package name" >&2 && exit 1
  echo "✅ README package identity is rendered from the scaffold values"
  exit 0
fi

[ ! -f "${archive}" ] && echo "❌ Package archive '${archive}' not found" >&2 && exit 1

if [ "${mode}" = "pack-content" ]; then
  contents="$(tar -tzf "${archive}")"
  expected_paths=(
    package/package.json
    package/README.md
    package/LICENSE
    package/skills/diene-frontend-utils-usage/SKILL.md
    package/skills/diene-frontend-utils-usage/agents/openai.yaml
    package/skills/diene-frontend-utils-usage/assets/consumer.ts
    package/skills/diene-frontend-utils-usage/assets/consumer-test.ts
  )
  while IFS= read -r artifact; do
    expected_paths+=("package/${artifact#./}")
  done < <(
    jq -r '
      .exports
      | to_entries[]
      | select(.value | type == "object")
      | .value
      | .import.types, .import.default, .require.types, .require.default
    ' package.json | sort -u
  )
  for expected in "${expected_paths[@]}"; do
    ! printf '%s\n' "${contents}" | rg -Fxq "${expected}" && echo "❌ Packed library is missing ${expected}" >&2 && exit 1
  done
  echo "✅ Packed library contains the declared artifacts and usage skill"
  exit 0
fi

if [ "${mode}" = "metadata" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT
  tar -xzf "${archive}" -C "${tmp}"
  manifest="${tmp}/package/package.json"
  package_name="$(jq -r '.name' "${manifest}")"
  repository="$(jq -r '.repository.url' "${manifest}" | sed -e 's#^git+##' -e 's#[.]git$##')"
  [[ ${package_name} != @atomicloud/* ]] && echo "❌ package name must use the @atomicloud scope" >&2 && exit 1
  [[ ${repository} != https://github.com/AtomiCloud/* ]] && echo "❌ repository URL must use the AtomiCloud organization" >&2 && exit 1
  [ "$(jq -r '.license' "${manifest}")" != "MIT" ] && echo "❌ package license metadata must be MIT" >&2 && exit 1
  ! rg -q '^MIT License$' "${tmp}/package/LICENSE" && echo "❌ root LICENSE does not match manifest metadata" >&2 && exit 1
  [ "$(jq -r '.publishConfig.access' "${manifest}")" != "public" ] && echo "❌ publishConfig.access must be public" >&2 && exit 1
  [ "$(jq -r '.sideEffects' "${manifest}")" != "false" ] && echo "❌ sideEffects must be false" >&2 && exit 1
  [ -z "$(jq -r '.description' "${manifest}")" ] && echo "❌ package description is missing" >&2 && exit 1
  [ "$(jq '.keywords | length' "${manifest}")" -lt 1 ] && echo "❌ package keywords are missing" >&2 && exit 1
  jq -e '
    .type == "module" and
    .main == "./dist/index.cjs" and
    .module == "./dist/index.js" and
    .types == "./dist/index.d.ts" and
    .exports["."].import.types == "./dist/index.d.ts" and
    .exports["."].import.default == "./dist/index.js" and
    .exports["."].require.types == "./dist/index.d.cts" and
    .exports["."].require.default == "./dist/index.cjs" and
    .repository.type == "git" and
    .engines.node == ">=18"
  ' "${manifest}" >/dev/null || {
    echo "❌ package identity or dual-format metadata is incomplete" >&2
    exit 1
  }
  [ "$(jq -r '.homepage' "${manifest}")" != "${repository}#readme" ] && echo "❌ package homepage must derive from repository.url" >&2 && exit 1
  [ "$(jq -r '.bugs.url' "${manifest}")" != "${repository}/issues" ] && echo "❌ package bugs URL must derive from repository.url" >&2 && exit 1
  echo "✅ Package metadata and root license agree"
  exit 0
fi

if [ "${mode}" = "publint" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT
  tar -xzf "${archive}" -C "${tmp}"
  ./node_modules/.bin/publint "${tmp}/package" --strict
  echo "✅ publint strict validation passed"
  exit 0
fi

./node_modules/.bin/attw "${archive}" --profile node16
echo "✅ Are The Types Wrong validation passed"
