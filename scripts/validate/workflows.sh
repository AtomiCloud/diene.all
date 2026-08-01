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

  # S31 cache eligibility is a property of what a job DOES, never of the labels it
  # already carries: a job is a Nix-store user because it installs Nix through a
  # setup action or runs a nix command that reads or writes the store. Deciding this
  # from the runs-on list would let a job drop '-with-cache' together with its cache
  # metadata and be silently reclassified as a deliberate isolation lane — the exact
  # shape that made live run 30670113046 fail.
  #
  # A step's 'uses:' is matched as text, because an action reference IS the whole
  # value. A step's 'run:' is a shell script, so it is read as one: only a Nix
  # command in command position counts, never a mention of one.
  nix_setup_action='AtomiCloud/actions[.]setup-nix|cachix/install-nix-action|DeterminateSystems/nix-installer-action|namespacelabs/nscloud-cache-action'

  # ---------------------------------------------------------------------------
  # run: scanner — invocation, not mention.
  #
  # 'echo nix develop' installs and uses nothing, so a substring match on the
  # script text hands a cache volume to a job that cannot use it. The scanner
  # below splits a run: script into shell words and asks whether a supported Nix
  # command stands in COMMAND position: at the start of the script, or after a
  # separator (newline ; & | ( ) ), optionally behind VAR=value assignments,
  # shell keywords, or a plain wrapper such as 'env' or 'sudo'. Quoted text,
  # comments and heredoc bodies never produce a command word.
  #
  # It is a small lexer, not a shell. Every construct it cannot read confidently
  # resolves to "no Nix invocation": a word that is quoted, escaped, expanded
  # ($VAR, backticks) or reached through an unreadable heredoc is left
  # unclassified. That is the fail-closed direction — a missed invocation only
  # refuses a cache claim (red), while a misread mention would grant the cache to
  # a job that never touches the store, which is the bypass this closes. A job
  # written in a form the scanner cannot read declares itself with a Nix setup
  # action instead.
  # ---------------------------------------------------------------------------
  nix_scanner="$(
    cat <<'JQ'
def nix_subcommands: ["develop", "build", "shell", "run", "flake", "profile", "store"];
def nix_legacy_commands: ["nix-build", "nix-shell", "nix-store"];
# Words that leave the NEXT word in command position.
def command_prefix_words: ["if", "then", "elif", "else", "while", "until", "do", "!", "command", "exec", "env", "nohup", "time", "sudo"];

# Heredoc bodies are data, so they are removed before any word is read. Openers
# are matched textually and generously: a '<<' that is really inside quotes only
# drops more lines than a shell would, and a '<<' whose delimiter cannot be read
# abandons the remainder of the script. Both directions lose invocations rather
# than invent them.
def heredoc_free:
  reduce (. / "\n")[] as $line (
    { pending: [], code: [], readable: true };
    if (.readable | not) then .
    elif (.pending | length) > 0 then
      (.pending[0]) as $open
      | if (if $open.strip then ($line | sub("^\t+"; "")) else $line end) == $open.delim
        then .pending = .pending[1:]
        else .
        end
    else
      ([$line | match("<<(-?)[ \t]*(?:'([^']*)'|\"([^\"]*)\"|([A-Za-z_][A-Za-z0-9_.-]*))"; "g")
        | { strip: (.captures[0].string == "-"),
            delim: ([.captures[1].string, .captures[2].string, .captures[3].string] | map(values) | first) }]) as $opens
      | if ($opens | length) != ([$line | match("(?<!<)<<(?!<)"; "g")] | length)
        then .readable = false
        else .code += [$line] | .pending += $opens
        end
    end
  )
  | if .readable then (.code | join("\n")) else null end;

# 'plain' records that a word was built only from literal, unquoted characters.
# A word that is not plain is never matched against a Nix command name.
def tok_flush: if .started then .out += [{ w: .tok, plain: .plain }] | .tok = "" | .plain = true | .started = false else . end;
def tok_sep: tok_flush | .out += [{ sep: true }];

def shell_words:
  reduce (. / "")[] as $c (
    { mode: "code", esc: false, tok: "", plain: true, started: false, out: [] };
    if .esc then
      (if .mode == "code" and $c != "\n" then .tok += $c | .plain = false | .started = true else . end) | .esc = false
    elif .mode == "single" then (if $c == "'" then .mode = "code" else . end)
    elif .mode == "double" then (if $c == "\\" then .esc = true elif $c == "\"" then .mode = "code" else . end)
    elif .mode == "backtick" then (if $c == "`" then .mode = "code" else . end)
    elif .mode == "comment" then (if $c == "\n" then .mode = "code" | tok_sep else . end)
    elif $c == "\\" then .esc = true
    elif $c == "'" then .mode = "single" | .plain = false | .started = true
    elif $c == "\"" then .mode = "double" | .plain = false | .started = true
    elif $c == "`" then .mode = "backtick" | .plain = false | .started = true
    elif $c == "#" and (.started | not) then .mode = "comment"
    elif $c == "$" then .plain = false | .started = true
    elif ($c == " " or $c == "\t") then tok_flush
    elif ($c == "\n" or $c == ";" or $c == "&" or $c == "|" or $c == "(" or $c == ")") then tok_sep
    else .tok += $c | .started = true
    end
  )
  | tok_flush
  | .out;

# 'nix' is a multiplexer, so it counts only when the very next word is one of the
# store-using subcommands: 'nix --version' and a lone 'nix' are not store use,
# and a flag before the subcommand is left unread rather than guessed at.
def nix_invoked:
  reduce .[] as $t (
    { cmdpos: true, want_sub: false, found: false };
    if .found then .
    elif ($t.sep // false) then .cmdpos = true | .want_sub = false
    elif .want_sub then
      .want_sub = false
      | if ($t.plain and ((nix_subcommands | index($t.w)) != null)) then .found = true else . end
    elif .cmdpos then
      if ($t.plain | not) then .cmdpos = false
      elif ($t.w | test("^[A-Za-z_][A-Za-z0-9_]*=")) then .
      elif ((command_prefix_words | index($t.w)) != null) then .
      elif $t.w == "nix" then .cmdpos = false | .want_sub = true
      elif ((nix_legacy_commands | index($t.w)) != null) then .found = true
      else .cmdpos = false
      end
    else .
    end
  )
  | .found;

def run_invokes_nix:
  heredoc_free as $code
  | if $code == null then false else ($code | shell_words | nix_invoked) end;
JQ
  )"

  find .github/workflows -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 | while IFS= read -r -d '' file; do
    yq -o=json "${file}" | jq -r --arg file "${file}" --arg setup "${nix_setup_action}" "${nix_scanner}"'
      . as $workflow |
      (.jobs // {}) | to_entries[] | select(.value["runs-on"] != null) | . as $entry | .value as $job |
      [
        $file,
        $entry.key,
        ($job["runs-on"] | type),
        (if ($job["runs-on"] | type) == "array" then ($job["runs-on"] | join(",")) else $job["runs-on"] end),
        (($job.env.S31_RUNNER_FALLBACK_REASON // "") | tostring),
        (($job.env.S31_CACHE_EXEMPT_REASON // "") | tostring),
        (if ([($job.steps // [])[] | ((.uses // "") | tostring)] | any(test($setup)))
            or ([($job.steps // [])[] | ((.run // "") | tostring)] | any(run_invokes_nix))
         then "nix-store-user"
         else "no-nix"
         end),
        ([
          (if (($workflow.env // {}) | has("S31_CACHE_EXEMPT_REASON")) then "workflow-level env.S31_CACHE_EXEMPT_REASON" else empty end),
          (if (($workflow.env // {}) | has("S31_RUNNER_FALLBACK_REASON")) then "workflow-level env.S31_RUNNER_FALLBACK_REASON" else empty end),
          (if ([($job.steps // [])[] | ((.env // {}) | keys[])] | index("S31_CACHE_EXEMPT_REASON")) then "step-level env.S31_CACHE_EXEMPT_REASON" else empty end),
          (if ([($job.steps // [])[] | ((.env // {}) | keys[])] | index("S31_RUNNER_FALLBACK_REASON")) then "step-level env.S31_RUNNER_FALLBACK_REASON" else empty end)
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
  while IFS=$'\037' read -r file job runner_type runners fallback_reason exempt_reason nix_use misplaced_markers; do
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

    # Both S31 markers are job-level records. A marker parked on a step or on the
    # workflow cannot state which lane it excuses, so it is rejected as misplaced
    # rather than read as an exemption.
    [ -n "${misplaced_markers}" ] && echo "❌ ${file} job '${job}' must declare S31 markers in job-level env, not ${misplaced_markers}" >&2 && exit 1

    # A whitespace-only marker is not a record, so emptiness is tested on the
    # stripped value while the authored text stays available for messages.
    fallback_recorded="${fallback_reason//[[:space:]]/}"
    cache_exemption="${exempt_reason//[[:space:]]/}"

    venue_count=$((namespace_cache_primary + namespace_cache_fallback + namespace_bare_primary + namespace_bare_fallback + github_primary + github_fallback))
    [ "${venue_count}" -ne 1 ] && echo "❌ ${file} job '${job}' must select exactly one S31 primary or fallback venue label" >&2 && exit 1

    cache_capable=$((namespace_cache_primary + namespace_cache_fallback))
    namespace_venue=$((cache_capable + namespace_bare_primary + namespace_bare_fallback))

    if [ "${namespace_venue}" -eq 1 ]; then
      [ "${runner_type}" != "array" ] && echo "❌ ${file} job '${job}' must declare Namespace runner metadata as an array" >&2 && exit 1
      if [ "${cache_capable}" -eq 1 ]; then
        [ "${nix_use}" != "nix-store-user" ] && echo "❌ ${file} job '${job}' claims the shared S31 Nix-store cache but is not a Nix-store user (no Nix setup action and no nix command in its steps)" >&2 && exit 1
        [ -n "${cache_exemption}" ] && echo "❌ ${file} job '${job}' records env.S31_CACHE_EXEMPT_REASON while selecting a cache-capable -with-cache venue" >&2 && exit 1
        [ "${cache_size_count}" -ne 1 ] && echo "❌ ${file} job '${job}' must have exactly one Namespace cache-size label" >&2 && exit 1
        [ "${cache_tag_count}" -ne 1 ] && echo "❌ ${file} job '${job}' must have exactly one nscloud cache tag" >&2 && exit 1
        expected_tag="nscloud-cache-tag-atomi-nix-store-cache-ubuntu-26.04-amd64"
        [ "${namespace_cache_fallback}" -eq 1 ] && expected_tag="nscloud-cache-tag-atomi-nix-store-cache-ubuntu-24.04-amd64"
        [ "${cache_tag}" != "${expected_tag}" ] && echo "❌ ${file} job '${job}' cache tag must be '${expected_tag}', got '${cache_tag}'" >&2 && exit 1
        cache_eligible_checked=$((cache_eligible_checked + 1))
      else
        [ "${cache_size_count}" -ne 0 ] && echo "❌ ${file} job '${job}' must not attach Namespace cache metadata to a bare venue" >&2 && exit 1
        [ "${cache_tag_count}" -ne 0 ] && echo "❌ ${file} job '${job}' must not attach a Namespace cache tag to a bare venue" >&2 && exit 1
        if [ "${nix_use}" = "nix-store-user" ]; then
          # A bare venue cannot attach a cache volume, so a Nix-store user on one is
          # either a mistake or the deliberate must-not-share-cache lane the threat
          # model allows — and only the recorded reason tells the two apart.
          [ -z "${cache_exemption}" ] && echo "❌ ${file} job '${job}' uses the Nix store on a bare venue that cannot attach a cache volume: select the -with-cache venue with its cache-size and cache-tag labels, or record env.S31_CACHE_EXEMPT_REASON" >&2 && exit 1
          cache_exempt_checked=$((cache_exempt_checked + 1))
        else
          [ -n "${cache_exemption}" ] && echo "❌ ${file} job '${job}' records env.S31_CACHE_EXEMPT_REASON without using the Nix store, so there is no shared cache for it to be exempt from" >&2 && exit 1
        fi
        namespace_bare_checked=$((namespace_bare_checked + 1))
      fi
      namespace_checked=$((namespace_checked + 1))
    else
      [ "${runner_type}" != "string" ] && echo "❌ ${file} job '${job}' must declare its GitHub-hosted runner as one scalar label" >&2 && exit 1
      [ "${cache_size_count}" -ne 0 ] && echo "❌ ${file} job '${job}' must not attach Namespace cache metadata to a GitHub-hosted runner" >&2 && exit 1
      [ "${cache_tag_count}" -ne 0 ] && echo "❌ ${file} job '${job}' must not attach a Namespace cache tag to a GitHub-hosted runner" >&2 && exit 1
      # The must-not-share-cache lane is a Namespace venue by ruling, so a GitHub-hosted
      # runner is never a legal home for a Nix-store user and no recorded reason makes it
      # one. Both refusals below are unconditional on purpose.
      [ "${nix_use}" = "nix-store-user" ] && echo "❌ ${file} job '${job}' uses the Nix store on a GitHub-hosted runner: select the cache-capable Namespace venue, or the bare Namespace venue with env.S31_CACHE_EXEMPT_REASON if it must not share the store" >&2 && exit 1
      [ -n "${cache_exemption}" ] && echo "❌ ${file} job '${job}' records env.S31_CACHE_EXEMPT_REASON on a GitHub-hosted runner, which never attaches a Namespace cache" >&2 && exit 1
      github_checked=$((github_checked + 1))
    fi

    if [ $((namespace_cache_fallback + namespace_bare_fallback + github_fallback)) -eq 1 ]; then
      [ -z "${fallback_recorded}" ] && echo "❌ ${file} job '${job}' selects an S31 fallback without env.S31_RUNNER_FALLBACK_REASON" >&2 && exit 1
    else
      [ -n "${fallback_recorded}" ] && echo "❌ ${file} job '${job}' records a fallback reason while selecting the primary runner" >&2 && exit 1
    fi

    checked=$((checked + 1))
  done <"${tmp}"

  [ "${github_checked}" -eq 0 ] && echo "❌ no GitHub-hosted S31 runner declaration was checked" >&2 && exit 1
  [ "${namespace_checked}" -eq 0 ] && echo "❌ no Namespace S31 runner declaration was checked" >&2 && exit 1
  [ "${cache_eligible_checked}" -eq 0 ] && echo "❌ no cache-eligible Namespace S31 runner/cache declaration was checked" >&2 && exit 1
  # Those three guards also keep the behavioural classification itself non-vacuous, in
  # both directions and without a fourth counter: a cache-capable venue is rejected for
  # any job that is not a Nix-store user, so a non-zero cache-eligible count proves the
  # classifier said "Nix" at least once; a GitHub-hosted runner is rejected for any job
  # that IS one, so a non-zero GitHub count proves it said "not Nix" at least once. A
  # classifier stuck at either answer turns one of them red.
  echo "✅ S31 runner labels and cache tags conform across ${checked} jobs (${cache_eligible_checked} cached Nix-store, ${cache_exempt_checked} exempt Nix-store, ${namespace_bare_checked} bare Namespace, ${github_checked} GitHub-hosted)"
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
