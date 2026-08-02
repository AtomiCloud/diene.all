#!/usr/bin/env bash
set -euo pipefail

# A self-contained step delegates to exactly one repository script, so shell operators mean inline CI logic.
entrypoint='^nix develop \.#ci -c (\./scripts/ci/[A-Za-z0-9._-]+\.sh)( [^;&|<>`()]*)?$'
cache='AtomiCloud/actions.cache-go@v2'

# Resolve the Go workflow population first so an empty set fails instead of passing vacuously.
shopt -s nullglob
workflows=(.github/workflows/⚡reusable-go-*.yaml)
shopt -u nullglob
[ "${#workflows[@]}" -eq 0 ] && echo "❌ no '⚡reusable-go-*.yaml' workflow exists under '.github/workflows'" >&2 && exit 1

for workflow in "${workflows[@]}"; do
  # Read through the YAML parser: a Go workflow the parser cannot read is unverifiable, not compliant.
  jobs_status=0
  jobs="$(yq -r '.jobs | to_entries[] | .key' "${workflow}" 2>&1)" || jobs_status=$?
  [ "${jobs_status}" -ne 0 ] && echo "❌ could not parse Go reusable workflow '${workflow}': ${jobs}" >&2 && exit 1
  [ -z "${jobs}" ] && echo "❌ Go reusable workflow '${workflow}' declares no jobs" >&2 && exit 1

  while IFS= read -r job; do
    # Mark an absent field so tab splitting cannot merge a run command into the uses column.
    steps_status=0
    steps="$(job="${job}" yq -r '.jobs[strenv(job)].steps[] | [(.uses // "-"), (.run // "-" | sub("\n"; "<newline>"))] | join("\t")' "${workflow}" 2>&1)" || steps_status=$?
    [ "${steps_status}" -ne 0 ] && echo "❌ could not read steps of '${workflow}' job '${job}': ${steps}" >&2 && exit 1
    [ -z "${steps}" ] && echo "❌ '${workflow}' job '${job}' declares no steps" >&2 && exit 1

    called=""
    cached=""
    while IFS=$'\t' read -r uses run; do
      [ "${uses}" = "${cache}" ] && cached="yes"
      [ "${run}" = "-" ] && continue
      [[ ${run} =~ ${entrypoint} ]] || {
        echo "❌ '${workflow}' job '${job}' runs inline CI logic instead of a scripts/ci entrypoint: '${run}'" >&2
        exit 1
      }
      script="${BASH_REMATCH[1]#./}"
      [ ! -f "${script}" ] && echo "❌ '${workflow}' job '${job}' references missing script '${script}'" >&2 && exit 1
      [ ! -x "${script}" ] && echo "❌ '${workflow}' job '${job}' references non-executable script '${script}'" >&2 && exit 1
      called="yes"
    done <<<"${steps}"

    # A Go job that reaches the toolchain without a script escapes this gate entirely.
    [ -z "${called}" ] && echo "❌ '${workflow}' job '${job}' calls no scripts/ci entrypoint" >&2 && exit 1
    # Cache wiring is required exactly where Go actually runs, which is every job holding an entrypoint.
    [ -n "${cached}" ] || {
      echo "❌ '${workflow}' job '${job}' runs Go without the '${cache}' cache step" >&2
      exit 1
    }
  done <<<"${jobs}"
done

echo "✅ Go reusable workflows resolve to cached, self-contained CI scripts"
