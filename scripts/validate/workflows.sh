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

  # ---------------------------------------------------------------------------
  # The rule this mode enforces, in full:
  #
  #   Every CI job either
  #     (a) runs its work inside a dev shell that declares its dependencies, and
  #         therefore selects the cache-capable Namespace venue with the shared
  #         Nix-store cache labels; or
  #     (b) is a deliberate isolation lane — the bare Namespace venue, no cache
  #         labels, and a non-empty job-level env.NIX_CACHE_EXEMPT_REASON saying
  #         why it must not share the store; or
  #     (c) runs no repository script at all (no run: step, no Nix setup action),
  #         in which case it uses no Nix store, carries no cache labels, and may
  #         sit on a GitHub-hosted runner.
  #
  # This replaced a shell lexer that tried to decide, from the text of each run:
  # script, whether a Nix command "definitely runs", "definitely does not run", or
  # "cannot be read". That machinery existed only because a job was allowed to run
  # a script outside a shell: the gate then had to guess whether the script touched
  # the store. Requiring the shell removes the question. Every run: step must ENTER
  # a declared shell, which is one line to match — so the answer is now yes or no,
  # and there is nothing left to guess at.
  #
  # It is also strictly stronger, not merely smaller. The lexer could refuse only
  # what it could not read; a script it read as "not Nix" was allowed to run bare.
  # Now a bare command is refused outright, whatever it is.
  # ---------------------------------------------------------------------------

  # The dev shells that exist, read from the file that composes them rather than
  # hardcoded here: a job may only enter a shell this repository actually declares,
  # so 'nix develop .#typo' is a refusal here instead of a failure in CI.
  # '|| true' is load-bearing: rg exits 1 when it matches nothing, and under
  # `set -e` a bare command substitution would abort the script right here — the
  # guard below would never run and the operator would get a non-zero exit with no
  # message at all. The refusal has to be reachable to be a refusal.
  declared_shells="$(rg -o --no-filename '^  ([A-Za-z][A-Za-z0-9_-]*) = pkgs\.mkShell \{' -r '$1' nix/shells.nix 2>/dev/null | sort -u || true)"
  [ -z "${declared_shells}" ] &&
    echo "❌ no dev shell declarations were found in nix/shells.nix: either the shell set moved or this gate's parser is broken" >&2 &&
    exit 1
  shell_alternation="$(printf '%s' "${declared_shells}" | paste -sd'|' -)"
  shell_list="$(printf '%s' "${declared_shells}" | paste -sd'/' -)"

  nix_setup_action='AtomiCloud/actions[.]setup-nix|cachix/install-nix-action|DeterminateSystems/nix-installer-action|namespacelabs/nscloud-cache-action'

  # A run: step conforms when its script is exactly ONE command that enters a
  # declared shell. One command, because a multi-line script could enter a shell on
  # its first line and then run anything at all on its second: the shell would be
  # declared and the work would still escape it. \A and \z rather than ^ and $ for
  # the same reason — in this regex dialect ^ and $ match at line boundaries, so an
  # anchored-looking pattern would match the first line of a longer script.
  run_pattern="\\Anix develop \\.#(${shell_alternation}) -c [^[:space:]]+( [^\\n]*)?\\z"

  find .github/workflows -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 | while IFS= read -r -d '' file; do
    yq -o=json "${file}" | jq -r \
      --arg file "${file}" \
      --arg setup "${nix_setup_action}" \
      --arg runpat "${run_pattern}" '
      def trim: sub("\\A[[:space:]]+"; "") | sub("[[:space:]]+\\z"; "");
      . as $workflow |
      (.jobs // {}) | to_entries[] | select(.value["runs-on"] != null) | . as $entry | .value as $job |
      ([($job.steps // [])[] | select(has("run")) | (.run | tostring)]) as $runs |
      [
        $file,
        $entry.key,
        ($job["runs-on"] | type),
        (if ($job["runs-on"] | type) == "array" then ($job["runs-on"] | join(",")) else $job["runs-on"] end),
        (($job.env.NIX_RUNNER_FALLBACK_REASON // "") | tostring),
        (($job.env.NIX_CACHE_EXEMPT_REASON // "") | tostring),
        ($runs | length | tostring),
        # Every run: script that does NOT enter a declared shell, reported by its
        # first line so the refusal names the offending step, not just the job.
        ([$runs[] | select((trim | test($runpat)) | not) | (split("\n")[0] | trim)] | join(" ; ")),
        # A step-level uses: pointing into this repository would be a local composite
        # action, whose own steps this gate never sees.
        ([($job.steps // [])[] | ((.uses // "") | tostring) | select(startswith("./"))] | join(" ; ")),
        (if ([($job.steps // [])[] | ((.uses // "") | tostring)] | any(test($setup))) then "yes" else "no" end),
        ([
          (if (($workflow.env // {}) | has("NIX_CACHE_EXEMPT_REASON")) then "workflow-level env.NIX_CACHE_EXEMPT_REASON" else empty end),
          (if (($workflow.env // {}) | has("NIX_RUNNER_FALLBACK_REASON")) then "workflow-level env.NIX_RUNNER_FALLBACK_REASON" else empty end),
          (if ([($job.steps // [])[] | ((.env // {}) | keys[])] | index("NIX_CACHE_EXEMPT_REASON")) then "step-level env.NIX_CACHE_EXEMPT_REASON" else empty end),
          (if ([($job.steps // [])[] | ((.env // {}) | keys[])] | index("NIX_RUNNER_FALLBACK_REASON")) then "step-level env.NIX_RUNNER_FALLBACK_REASON" else empty end)
        ] | join(", "))
      ]
      # Unit separators, not tabs: a tab is IFS whitespace, so two adjacent empty
      # fields would collapse into one and shift every later column.
      | map(tostring | gsub("[[:cntrl:]]"; " ")) | join("\u001f")
    '
  done >"${tmp}"

  [ ! -s "${tmp}" ] && echo "❌ no workflow jobs with runs-on declarations were found" >&2 && exit 1

  checked=0
  github_checked=0
  namespace_checked=0
  cache_eligible_checked=0
  cache_exempt_checked=0
  namespace_bare_checked=0
  run_steps_checked=0
  while IFS=$'\037' read -r file job runner_type runners fallback_reason exempt_reason run_count shell_less local_actions has_nix_setup misplaced_markers; do
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

    # A local composite action can hold run: steps of its own, which this gate reads
    # nothing of, so it is a route around the declared-shell rule rather than a use
    # of it. Refused before the shell check, because it would make that check
    # vacuous for this job.
    [ -n "${local_actions}" ] &&
      echo "❌ ${file} job '${job}' uses a repository-local composite action (${local_actions}): its steps are invisible to this gate, so put the work in a scripts/ci entry point and run it through a declared Nix shell instead" >&2 &&
      exit 1

    # THE RULE. Every run: step enters a dev shell that declares its dependencies.
    # This is what makes every job cache-eligible, and it is why this gate no longer
    # needs to reason about what a script might do.
    [ -n "${shell_less}" ] &&
      echo "❌ ${file} job '${job}' has a run: step that does not enter a declared Nix shell (${shell_less}): every run: step must be exactly one 'nix develop .#<shell> -c <command>', where <shell> is one of ${shell_list}" >&2 &&
      exit 1

    # Both markers are job-level records. A marker parked on a step or on the
    # workflow cannot state which lane it excuses, so it is rejected as misplaced
    # rather than read as an exemption.
    [ -n "${misplaced_markers}" ] && echo "❌ ${file} job '${job}' must declare its cache markers in job-level env, not ${misplaced_markers}" >&2 && exit 1

    # A whitespace-only marker is not a record, so emptiness is tested on the
    # stripped value while the authored text stays available for messages.
    fallback_recorded="${fallback_reason//[[:space:]]/}"
    cache_exemption="${exempt_reason//[[:space:]]/}"

    venue_count=$((namespace_cache_primary + namespace_cache_fallback + namespace_bare_primary + namespace_bare_fallback + github_primary + github_fallback))
    [ "${venue_count}" -ne 1 ] && echo "❌ ${file} job '${job}' must select exactly one primary or fallback venue label" >&2 && exit 1

    cache_capable=$((namespace_cache_primary + namespace_cache_fallback))
    namespace_venue=$((cache_capable + namespace_bare_primary + namespace_bare_fallback))

    # A job uses the Nix store because it enters a shell or installs Nix — both are
    # declarations, not inferences. A job with neither runs no repository script and
    # is the third class: pure GitHub Actions orchestration.
    nix_store_user="no"
    { [ "${run_count}" -gt 0 ] || [ "${has_nix_setup}" = "yes" ]; } && nix_store_user="yes"
    run_steps_checked=$((run_steps_checked + run_count))

    if [ "${namespace_venue}" -eq 1 ]; then
      [ "${runner_type}" != "array" ] && echo "❌ ${file} job '${job}' must declare Namespace runner metadata as an array" >&2 && exit 1
      if [ "${cache_capable}" -eq 1 ]; then
        [ "${nix_store_user}" != "yes" ] && echo "❌ ${file} job '${job}' claims the shared Nix-store cache but runs no repository script: it has no run: step and no Nix setup action, so there is no store for it to share" >&2 && exit 1
        [ -n "${cache_exemption}" ] && echo "❌ ${file} job '${job}' records env.NIX_CACHE_EXEMPT_REASON while selecting a cache-capable -with-cache venue" >&2 && exit 1
        [ "${cache_size_count}" -ne 1 ] && echo "❌ ${file} job '${job}' must have exactly one Namespace cache-size label" >&2 && exit 1
        [ "${cache_tag_count}" -ne 1 ] && echo "❌ ${file} job '${job}' must have exactly one nscloud cache tag" >&2 && exit 1
        expected_tag="nscloud-cache-tag-nix-store-cache-ubuntu-26.04-amd64"
        [ "${namespace_cache_fallback}" -eq 1 ] && expected_tag="nscloud-cache-tag-nix-store-cache-ubuntu-24.04-amd64"
        [ "${cache_tag}" != "${expected_tag}" ] && echo "❌ ${file} job '${job}' cache tag must be '${expected_tag}', got '${cache_tag}'" >&2 && exit 1
        cache_eligible_checked=$((cache_eligible_checked + 1))
      else
        [ "${cache_size_count}" -ne 0 ] && echo "❌ ${file} job '${job}' must not attach Namespace cache metadata to a bare venue" >&2 && exit 1
        [ "${cache_tag_count}" -ne 0 ] && echo "❌ ${file} job '${job}' must not attach a Namespace cache tag to a bare venue" >&2 && exit 1
        if [ "${nix_store_user}" = "yes" ]; then
          # A bare venue cannot attach a cache volume, so a job that uses the store on
          # one is either a mistake or the deliberate isolation lane the threat model
          # allows — and only the recorded reason tells the two apart.
          [ -z "${cache_exemption}" ] && echo "❌ ${file} job '${job}' runs in a Nix shell on a bare venue that cannot attach a cache volume: select the -with-cache venue with its cache-size and cache-tag labels, or record env.NIX_CACHE_EXEMPT_REASON to declare it an isolation lane" >&2 && exit 1
          cache_exempt_checked=$((cache_exempt_checked + 1))
        else
          [ -n "${cache_exemption}" ] && echo "❌ ${file} job '${job}' records env.NIX_CACHE_EXEMPT_REASON without running any repository script, so there is no shared cache for it to be exempt from" >&2 && exit 1
        fi
        namespace_bare_checked=$((namespace_bare_checked + 1))
      fi
      namespace_checked=$((namespace_checked + 1))
    else
      [ "${runner_type}" != "string" ] && echo "❌ ${file} job '${job}' must declare its GitHub-hosted runner as one scalar label" >&2 && exit 1
      [ "${cache_size_count}" -ne 0 ] && echo "❌ ${file} job '${job}' must not attach Namespace cache metadata to a GitHub-hosted runner" >&2 && exit 1
      [ "${cache_tag_count}" -ne 0 ] && echo "❌ ${file} job '${job}' must not attach a Namespace cache tag to a GitHub-hosted runner" >&2 && exit 1
      # The isolation lane is a Namespace venue by ruling, so a GitHub-hosted runner is
      # never a legal home for a job that runs a repository script, and no recorded
      # reason makes it one. Both refusals below are unconditional on purpose.
      [ "${nix_store_user}" = "yes" ] && echo "❌ ${file} job '${job}' runs a repository script on a GitHub-hosted runner: every such job runs in a declared Nix shell, so select the cache-capable Namespace venue, or the bare Namespace venue with env.NIX_CACHE_EXEMPT_REASON if it must not share the store" >&2 && exit 1
      [ -n "${cache_exemption}" ] && echo "❌ ${file} job '${job}' records env.NIX_CACHE_EXEMPT_REASON on a GitHub-hosted runner, which never attaches a Namespace cache" >&2 && exit 1
      github_checked=$((github_checked + 1))
    fi

    if [ $((namespace_cache_fallback + namespace_bare_fallback + github_fallback)) -eq 1 ]; then
      [ -z "${fallback_recorded}" ] && echo "❌ ${file} job '${job}' selects a fallback runner without env.NIX_RUNNER_FALLBACK_REASON" >&2 && exit 1
    else
      [ -n "${fallback_recorded}" ] && echo "❌ ${file} job '${job}' records a fallback reason while selecting the primary runner" >&2 && exit 1
    fi

    checked=$((checked + 1))
  done <"${tmp}"

  # Four non-vacuity guards, each closing a way this gate could pass while checking
  # nothing:
  #  - run_steps_checked proves the declared-shell rule was applied to at least one
  #    real run: step, so a workflow set that lost every run: step cannot read as
  #    compliant;
  #  - cache_eligible_checked proves at least one job took the cached venue, which is
  #    refused for a job that runs no script — so the classification said "uses the
  #    store" at least once;
  #  - github_checked proves at least one job took a hosted runner, which is refused
  #    for a job that DOES run one — so it said "runs no script" at least once;
  #  - namespace_checked proves the Namespace branch itself was exercised.
  # A classification stuck at either answer turns one of these red.
  [ "${run_steps_checked}" -eq 0 ] && echo "❌ no run: step was checked against the declared-shell rule" >&2 && exit 1
  [ "${cache_eligible_checked}" -eq 0 ] && echo "❌ no cache-eligible Namespace runner/cache declaration was checked" >&2 && exit 1
  [ "${namespace_checked}" -eq 0 ] && echo "❌ no Namespace runner declaration was checked" >&2 && exit 1
  [ "${github_checked}" -eq 0 ] && echo "❌ no GitHub-hosted runner declaration was checked" >&2 && exit 1
  echo "✅ every job declares its dependencies and its cache: ${checked} jobs, ${run_steps_checked} run: steps in declared shells (${cache_eligible_checked} cached, ${cache_exempt_checked} isolation lanes, ${namespace_bare_checked} bare Namespace, ${github_checked} GitHub-hosted script-free)"
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
