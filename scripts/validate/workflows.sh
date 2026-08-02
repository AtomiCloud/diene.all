#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ "${mode}" != "wiring" ] && [ "${mode}" != "release-trigger" ] && [ "${mode}" != "release-concurrency" ] && echo "❌ unsupported workflow validation mode" >&2 && exit 1

if [ "${mode}" = "wiring" ]; then
  # Extract outside the loop so a scanner crash fails instead of reading as empty.
  scan_status=0
  scripts="$(rg -o --no-filename 'scripts/ci/[A-Za-z0-9._-]+[.]sh' .github/workflows | sort -u)" || scan_status=$?
  [ "${scan_status}" -gt 1 ] && echo "❌ could not scan '.github/workflows' for CI script references" >&2 && exit 1
  [ -z "${scripts}" ] && echo "❌ no workflow references a scripts/ci entrypoint" >&2 && exit 1

  while IFS= read -r script; do
    [ -f "${script}" ] || {
      echo "❌ workflow references missing script '${script}'" >&2
      exit 1
    }
    [ -x "${script}" ] || {
      echo "❌ workflow script '${script}' is not executable" >&2
      exit 1
    }
  done <<<"${scripts}"

  for orchestrator in .github/workflows/ci.yaml .github/workflows/cd.yaml .github/workflows/release.yaml; do
    parse_status=0
    jobs="$(yq -r '.jobs | to_entries[] | [.key, (.value.uses // "")] | @tsv' "${orchestrator}")" || parse_status=$?
    [ "${parse_status}" -ne 0 ] && echo "❌ could not parse jobs from '${orchestrator}'" >&2 && exit 1
    [ -z "${jobs}" ] && echo "❌ '${orchestrator}' declares no jobs" >&2 && exit 1

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
      # An unparseable reusable workflow is unverifiable, not compliant.
      target_status=0
      target_jobs="$(yq -r '.jobs | to_entries[] | .key' "${target}")" || target_status=$?
      [ "${target_status}" -ne 0 ] && echo "❌ could not parse reusable workflow '${target}'" >&2 && exit 1
      [ -z "${target_jobs}" ] && echo "❌ reusable workflow '${target}' declares no jobs" >&2 && exit 1
      entrypoint_status=0
      rg -q 'scripts/ci/[A-Za-z0-9._-]+[.]sh' "${target}" || entrypoint_status=$?
      [ "${entrypoint_status}" -gt 1 ] && echo "❌ could not scan reusable workflow '${target}'" >&2 && exit 1
      [ "${entrypoint_status}" -eq 1 ] && echo "❌ reusable workflow '${target}' does not call a scripts/ci entrypoint" >&2 && exit 1
    done <<<"${jobs}"
  done

  echo "✅ Workflow jobs resolve to existing CI scripts"
  exit 0
fi

if [ "${mode}" = "release-trigger" ]; then
  yq -o=json .github/workflows/release.yaml | jq -e '.on.workflow_run.workflows == ["CI"]' >/dev/null || {
    echo "❌ release must trigger from CI" >&2
    exit 1
  }
  yq -o=json .github/workflows/release.yaml | jq -e '.on.workflow_run.branches == ["main"]' >/dev/null || {
    echo "❌ release must be limited to main" >&2
    exit 1
  }
  yq -o=json .github/workflows/release.yaml | jq -e '.on.workflow_run.types == ["completed"]' >/dev/null || {
    echo "❌ release workflow_run type must be completed" >&2
    exit 1
  }
  yq -o=json .github/workflows/release.yaml | jq -e '.jobs.release.if == "github.event.workflow_run.conclusion == '\''success'\''"' >/dev/null || {
    echo "❌ release job must require CI success" >&2
    exit 1
  }
  echo "✅ Release trigger conforms"
  exit 0
fi

yq -o=json .github/workflows/release.yaml | jq -e '.concurrency.group == "release"' >/dev/null || {
  echo "❌ release concurrency group must be release" >&2
  exit 1
}
echo "✅ Release concurrency conforms"
