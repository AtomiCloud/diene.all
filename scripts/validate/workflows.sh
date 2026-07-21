#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
workflow_dir="${WORKFLOW_DIR:-.github/workflows}"
release_workflow="${RELEASE_WORKFLOW:-${workflow_dir}/release.yaml}"
ci_workflow="${CI_WORKFLOW:-${workflow_dir}/ci.yaml}"
cd_workflow="${CD_WORKFLOW:-${workflow_dir}/cd.yaml}"
[ "${mode}" = "wiring" ] || {
  echo "❌ unsupported workflow validation mode" >&2
  exit 1
}

if [ "${mode}" = "wiring" ]; then
  while IFS= read -r script; do
    [ -f "${script}" ] || {
      echo "❌ workflow references missing script '${script}'" >&2
      exit 1
    }
    [ -x "${script}" ] || {
      echo "❌ workflow script '${script}' is not executable" >&2
      exit 1
    }
  done < <(rg -o --no-filename 'scripts/ci/[A-Za-z0-9._-]+[.]sh' "${workflow_dir}" | sort -u)

  for orchestrator in "${ci_workflow}" "${cd_workflow}" "${release_workflow}"; do
    while IFS=$'\t' read -r job reusable; do
      [ -z "${reusable}" ] && echo "❌ '${orchestrator}' job '${job}' must call a reusable workflow" >&2 && exit 1
      [[ ${reusable} == ./.github/workflows/* ]] || {
        echo "❌ '${orchestrator}' job '${job}' must call a repository-local reusable workflow" >&2
        exit 1
      }
      target="${reusable#./}"
      [ -f "${target}" ] || {
        echo "❌ '${orchestrator}' references missing reusable workflow '${target}'" >&2
        exit 1
      }
      rg -q 'scripts/ci/[A-Za-z0-9._-]+[.]sh' "${target}" || {
        echo "❌ reusable workflow '${target}' does not call a scripts/ci entrypoint" >&2
        exit 1
      }
    done < <(yq -r '.jobs | to_entries[] | [.key, (.value.uses // "")] | @tsv' "${orchestrator}")
  done

  echo "✅ Workflow jobs resolve to existing CI scripts"
fi
