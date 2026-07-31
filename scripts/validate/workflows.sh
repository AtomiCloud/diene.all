#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ "${mode}" != "wiring" ] && [ "${mode}" != "release-trigger" ] && [ "${mode}" != "release-concurrency" ] && [ "${mode}" != "cache-tag-shape" ] && echo "❌ unsupported workflow validation mode" >&2 && exit 1

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
  done < <(rg -o --no-filename 'scripts/ci/[A-Za-z0-9._-]+[.]sh' .github/workflows | sort -u)

  for orchestrator in .github/workflows/ci.yaml .github/workflows/cd.yaml .github/workflows/release.yaml; do
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
  exit 0
fi

if [ "${mode}" = "cache-tag-shape" ]; then
  tmp="$(mktemp)"
  trap 'rm -f "${tmp}"' EXIT

  find .github/workflows -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 | while IFS= read -r -d '' file; do
    yq -o=json "${file}" | jq -r --arg file "${file}" '
      (.jobs // {}) | to_entries[] | select(.value["runs-on"] != null) |
      [
        $file,
        .key,
        (.value["runs-on"] | type),
        (if (.value["runs-on"] | type) == "array" then (.value["runs-on"] | join(",")) else .value["runs-on"] end),
        ((.value.env.S31_RUNNER_FALLBACK_REASON // "") | tostring)
      ] | @tsv
    '
  done >"${tmp}"

  [ ! -s "${tmp}" ] && echo "❌ no workflow jobs with runs-on declarations were found" >&2 && exit 1

  checked=0
  github_checked=0
  namespace_checked=0
  cache_eligible_checked=0
  while IFS=$'\t' read -r file job runner_type runners fallback_reason; do
    namespace_cache_primary=0
    namespace_cache_fallback=0
    namespace_bare_primary=0
    namespace_bare_fallback=0
    github_primary=0
    github_fallback=0
    cache_size_count=0
    cache_tag_count=0
    cache_tag=""
    unsupported_labels=""

    IFS=',' read -r -a runner_labels <<<"${runners}"
    for label in "${runner_labels[@]}"; do
      case "${label}" in
      nscloud-ubuntu-26.04-amd64-16x32-with-cache) namespace_cache_primary=$((namespace_cache_primary + 1)) ;;
      nscloud-ubuntu-24.04-amd64-16x32-with-cache) namespace_cache_fallback=$((namespace_cache_fallback + 1)) ;;
      nscloud-ubuntu-26.04-amd64-16x32) namespace_bare_primary=$((namespace_bare_primary + 1)) ;;
      nscloud-ubuntu-24.04-amd64-16x32) namespace_bare_fallback=$((namespace_bare_fallback + 1)) ;;
      ubuntu-26.04) github_primary=$((github_primary + 1)) ;;
      ubuntu-24.04) github_fallback=$((github_fallback + 1)) ;;
      nscloud-cache-size-50gb) cache_size_count=$((cache_size_count + 1)) ;;
      nscloud-cache-tag-*)
        cache_tag_count=$((cache_tag_count + 1))
        cache_tag="${label}"
        ;;
      *) unsupported_labels="${unsupported_labels}${unsupported_labels:+,}${label}" ;;
      esac
    done

    [ -n "${unsupported_labels}" ] && echo "❌ ${file} job '${job}' has unsupported runner labels '${unsupported_labels}'" >&2 && exit 1

    venue_count=$((namespace_cache_primary + namespace_cache_fallback + namespace_bare_primary + namespace_bare_fallback + github_primary + github_fallback))
    [ "${venue_count}" -ne 1 ] && echo "❌ ${file} job '${job}' must select exactly one S31 primary or fallback venue label" >&2 && exit 1

    if [ $((namespace_cache_primary + namespace_cache_fallback + namespace_bare_primary + namespace_bare_fallback)) -eq 1 ]; then
      [ "${runner_type}" != "array" ] && echo "❌ ${file} job '${job}' must declare Namespace runner metadata as an array" >&2 && exit 1
      if [ $((namespace_cache_primary + namespace_cache_fallback)) -eq 1 ]; then
        [ "${cache_size_count}" -ne 1 ] && echo "❌ ${file} job '${job}' must have exactly one Namespace cache-size label" >&2 && exit 1
        [ "${cache_tag_count}" -ne 1 ] && echo "❌ ${file} job '${job}' must have exactly one nscloud cache tag" >&2 && exit 1
        expected_tag="nscloud-cache-tag-atomi-nix-store-cache-ubuntu-26.04-amd64"
        [ "${namespace_cache_fallback}" -eq 1 ] && expected_tag="nscloud-cache-tag-atomi-nix-store-cache-ubuntu-24.04-amd64"
        [ "${cache_tag}" != "${expected_tag}" ] && echo "❌ ${file} job '${job}' cache tag must be '${expected_tag}', got '${cache_tag}'" >&2 && exit 1
        cache_eligible_checked=$((cache_eligible_checked + 1))
      else
        [ "${cache_size_count}" -ne 0 ] && echo "❌ ${file} job '${job}' must not attach Namespace cache metadata to a bare venue" >&2 && exit 1
        [ "${cache_tag_count}" -ne 0 ] && echo "❌ ${file} job '${job}' must not attach a Namespace cache tag to a bare venue" >&2 && exit 1
      fi
      namespace_checked=$((namespace_checked + 1))
    else
      [ "${runner_type}" != "string" ] && echo "❌ ${file} job '${job}' must declare its GitHub-hosted runner as one scalar label" >&2 && exit 1
      [ "${cache_size_count}" -ne 0 ] && echo "❌ ${file} job '${job}' must not attach Namespace cache metadata to a GitHub-hosted runner" >&2 && exit 1
      [ "${cache_tag_count}" -ne 0 ] && echo "❌ ${file} job '${job}' must not attach a Namespace cache tag to a GitHub-hosted runner" >&2 && exit 1
      github_checked=$((github_checked + 1))
    fi

    if [ $((namespace_cache_fallback + namespace_bare_fallback + github_fallback)) -eq 1 ]; then
      [ -z "${fallback_reason}" ] && echo "❌ ${file} job '${job}' selects an S31 fallback without env.S31_RUNNER_FALLBACK_REASON" >&2 && exit 1
    else
      [ -n "${fallback_reason}" ] && echo "❌ ${file} job '${job}' records a fallback reason while selecting the primary runner" >&2 && exit 1
    fi
    checked=$((checked + 1))
  done <"${tmp}"

  [ "${github_checked}" -eq 0 ] && echo "❌ no GitHub-hosted S31 runner declaration was checked" >&2 && exit 1
  [ "${namespace_checked}" -eq 0 ] && echo "❌ no Namespace S31 runner declaration was checked" >&2 && exit 1
  [ "${cache_eligible_checked}" -eq 0 ] && echo "❌ no cache-eligible Namespace S31 runner/cache declaration was checked" >&2 && exit 1
  echo "✅ S31 runner labels and cache tags conform across ${checked} jobs"
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
