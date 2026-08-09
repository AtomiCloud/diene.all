#!/usr/bin/env bash
set -euo pipefail

mode="${1:---llm}"
strict_filter="${DEAD_CODE_RULE_FILTER:-Unused|NeverInstantiated|NeverUsed|NotAccessed|NeverSubscribed|UnassignedField}"
llm_filter="${DEAD_CODE_LLM_RULE_FILTER:-.*}"
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
solution="$(find "${root}" -maxdepth 1 -name '*.slnx' 2>/dev/null | head -n 1)"

[ "${mode}" != "--strict" ] && [ "${mode}" != "--strict-all" ] && [ "${mode}" != "--strict-production" ] && [ "${mode}" != "--llm" ] && echo "❌ mode must be --strict, --strict-all, --strict-production, or --llm" >&2 && exit 1
[ -z "${solution}" ] && echo "❌ No .slnx solution found in ${root}" >&2 && exit 1

echo "🔧 Restoring repo-local .NET tools..."
dotnet tool restore >/dev/null

shopt -s nullglob
production_projects=("${root}"/App*/*.csproj "${root}"/Lib*/*.csproj)
[ "${#production_projects[@]}" -eq 0 ] && echo "❌ No App*/Lib* production projects found" >&2 && exit 1

failed=0

if [ "${mode}" = "--strict" ] || [ "${mode}" = "--strict-all" ]; then
  echo "🔍 Strict dead-code inspection: all projects"
  if dn-inspect "${solution}" --filter "${strict_filter}"; then
    echo "✅ all projects: no issues found"
  else
    failed=1
    echo "❌ all projects: issues found"
  fi
fi

if [ "${mode}" = "--strict" ] || [ "${mode}" = "--strict-production" ]; then
  echo "🔍 Strict dead-code inspection: production projects"
  if dn-inspect --projects "${production_projects[@]}" --filter "${strict_filter}"; then
    echo "✅ production projects: no issues found"
  else
    failed=1
    echo "❌ production projects: issues found"
  fi
fi

if [ "${mode}" = "--llm" ]; then
  echo "📝 LLM dead-code review: all projects"
  dn-inspect "${solution}" --filter "${llm_filter}" || true

  echo "📝 LLM dead-code review: production projects"
  dn-inspect --projects "${production_projects[@]}" --filter "${llm_filter}" || true
fi

[ "${failed}" -ne 0 ] && exit 1

echo "✅ Dead-code inspection complete"
