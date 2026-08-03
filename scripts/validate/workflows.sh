#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ "${mode}" != "wiring" ] && [ "${mode}" != "release-trigger" ] && [ "${mode}" != "release-concurrency" ] && [ "${mode}" != "cache-tag-shape" ] && [ "${mode}" != "workflow-names" ] && echo "❌ unsupported workflow validation mode" >&2 && exit 1

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
  # value. A step's 'run:' is a shell script, so it is read as one.
  nix_setup_action='AtomiCloud/actions[.]setup-nix|cachix/install-nix-action|DeterminateSystems/nix-installer-action|namespacelabs/nscloud-cache-action'

  # ---------------------------------------------------------------------------
  # run: scanner — three answers, because two are not enough.
  #
  # 'echo nix develop' installs and uses nothing, so a substring match on the
  # script text hands a cache volume to a job that cannot use it. But answering
  # only "Nix" or "not Nix" is equally wrong in the other direction: a real
  # invocation the reader cannot make out ('$CMD develop', 'sudo -u root nix
  # develop') would be recorded as "not Nix", and on the bare venue that silently
  # excuses a Nix job from both the cache labels AND the exemption marker. So the
  # scanner answers:
  #
  #   nix        a supported Nix command definitely runs
  #   plain      the script definitely runs no Nix command
  #   ambiguous  the script contains syntax this reader cannot resolve
  #
  # 'ambiguous' is refused on every venue (see below). It is not a failure of the
  # job — it is the gate declining to guess, and the answer is always the same:
  # declare the Nix setup action, or write the command so it can be read.
  #
  # How a word is read: the lexer resolves quoting ('nix' and "nix" are the word
  # nix) but never guesses at an expansion ($CMD, backticks) — such a word is
  # unresolved. Comments and heredoc bodies produce no words at all.
  #
  # How a command is found: the first word of a simple command, after VAR=value
  # assignments, leading redirections, shell keywords and plain wrappers (env,
  # sudo, command, …). A '(' opens a subshell only where a command may start, so
  # an array literal, an arithmetic expression, a function definition and a
  # parenthesised case pattern are data, not commands. 'sh -c <script>' is read by
  # scanning <script>.
  #
  # When a mention is inert: a Nix command name that appears as an ARGUMENT is
  # inert only when the command receiving it is known not to execute its
  # arguments (echo, printf, grep, test, case, …). Any other command receiving
  # the word 'nix' is ambiguous, because it may well run it.
  # ---------------------------------------------------------------------------
  nix_scanner="$(
    cat <<'JQ'
def nix_subcommands: ["develop", "build", "shell", "run", "flake", "profile", "store"];
def nix_command_names: ["nix", "nix-build", "nix-shell", "nix-store"];
def nix_legacy_commands: ["nix-build", "nix-shell", "nix-store"];
# A Nix command name standing as its own token inside a longer string. The
# boundaries exclude the characters a longer name or path would continue with, so
# 'nixpkgs' and '/nix/store' do not match while 'system("nix develop")' does.
def nix_token_pattern: "(^|[^A-Za-z0-9_./-])(nix|nix-build|nix-shell|nix-store)([^A-Za-z0-9_-]|$)";
# Words that leave the NEXT word in command position.
def shell_keywords: ["if", "then", "elif", "else", "while", "until", "do", "!", "{"];
# Commands that run their argument list as a command.
def command_wrappers: ["command", "exec", "env", "nohup", "time", "sudo", "doas", "nice", "ionice", "setsid", "stdbuf", "timeout", "taskset", "chroot", "runuser", "su", "xargs"];
def shell_interpreters: ["sh", "bash", "zsh", "dash", "ash", "ksh"];
# Commands that demonstrably do NOT execute their arguments, so a Nix command
# name handed to one of them is text. The set is deliberately small: anything
# that can delegate execution stays off it — git dispatches external
# subcommands, package managers and Bun run scripts, awk has system(), sed has
# 'e', and eval/xargs/find are executors outright. A Nix name given to any
# command not listed here is unreadable rather than assumed inert.
def inert_commands: [
  "echo", "printf", "print", ":", "true", "false", "test", "[", "[[", "case", "for", "select", "in",
  "declare", "typeset", "local", "export", "readonly", "unset", "set", "shift", "return", "exit",
  "break", "continue", "grep", "egrep", "fgrep", "rg", "cut", "tr", "sort", "uniq", "head", "tail",
  "wc", "cat", "tee", "ls", "mkdir", "rm", "cp", "mv", "ln", "touch", "chmod", "chown", "basename",
  "dirname", "pwd", "cd"
];

# A word carries its resolved literal value and whether that value is certain:
# 'nix' and "nix" resolve to nix, while $CMD and `cmd` do not resolve at all.
def tok_push:
  if .started then
    (if .hd_want == 1 then
       (if (.lit | test("<<-?[^<]*$"))
        then (.lit | capture("<<(?<s>-?)(?<d>[^<]*)$")) as $m
          | if $m.d == "" then .hd_want = 2 | .hd_strip = ($m.s == "-")
            else .hd_queue += [{ delim: $m.d, strip: ($m.s == "-") }] | .hd_want = 0
            end
        else .hd_want = 0 | .risky = true
        end)
     elif .hd_want == 2 then
       .hd_queue += [{ delim: .lit, strip: .hd_strip }] | .hd_want = 0 | (if .ok then . else .risky = true end)
     else . end)
    | .out += [{ lit: .lit, ok: .ok }]
    | .lit = "" | .ok = true | .started = false
  else . end;

def tok_sep($c): tok_push | .out += [{ sep: $c }];

# Where a '(' is a case pattern rather than a subshell: directly after the 'in'
# of a case, or after the ';;' that ends the previous branch.
def pattern_pos:
  (.out | length) as $n
  | (($n > 0) and (.out[$n - 1].lit? == "in"))
    or (($n > 1) and (.out[$n - 1].sep? == ";") and (.out[$n - 2].sep? == ";"));

def shell_words:
  reduce (. / "")[] as $c (
    { mode: "code", esc: false, prev: "", lit: "", ok: true, started: false, out: [],
      hd_want: 0, hd_strip: false, hd_queue: [], hd_line: "", risky: false };
    (
      if .mode == "heredoc" then
        (if $c == "\n" then
           ((if .hd_queue[0].strip then (.hd_line | sub("^\t+"; "")) else .hd_line end) as $line
            | if $line == .hd_queue[0].delim
              then .hd_queue = .hd_queue[1:] | (if (.hd_queue | length) == 0 then .mode = "code" else . end)
              else . end)
           | .hd_line = ""
         else .hd_line += $c end)
      elif .esc then
        (if .mode == "code" and $c == "\n" then . else .lit += $c | .started = true end) | .esc = false
      elif .mode == "single" then (if $c == "'" then .mode = "code" else .lit += $c end)
      elif .mode == "double" then
        (if $c == "\\" then .esc = true
         elif $c == "\"" then .mode = "code"
         elif $c == "`" then .mode = "backtick" | .ok = false | .risky = true
         elif $c == "$" then .lit += $c | .ok = false
         else .lit += $c end)
      elif .mode == "backtick" then (if $c == "`" then .mode = "code" else . end)
      elif .mode == "comment" then (if $c == "\n" then .mode = "code" | tok_sep($c) else . end)
      elif $c == "\\" then .esc = true
      elif $c == "'" then .mode = "single" | .started = true
      elif $c == "\"" then .mode = "double" | .started = true
      elif $c == "`" then .mode = "backtick" | .ok = false | .started = true | .risky = true
      elif $c == "#" and (.started | not) then .mode = "comment"
      elif $c == "$" then .lit += $c | .ok = false | .started = true
      elif ($c == " " or $c == "\t") then tok_push
      elif $c == "<" then
        # A second '<' opens a heredoc; a third makes it a here-string instead.
        (if .prev == "<" then (if .hd_want == 1 then .hd_want = 0 else .hd_want = 1 end) else . end)
        | .lit += $c | .started = true
      elif $c == "(" then
        # '(' opens a subshell only where a command may start. Directly after a
        # word it is an array literal or a function definition; doubled it is
        # arithmetic; after 'in' or ';;' it is a case pattern. The exceptions are
        # the expansion prefixes $( <( >( , which DO start a command.
        (if (.lit | test("[$<>]$")) then tok_sep($c)
         elif .started or (.prev == "(") or pattern_pos then .lit += $c | .started = true
         else tok_sep($c) end)
      elif $c == "\n" then
        tok_sep($c) | (if (.hd_queue | length) > 0 then .mode = "heredoc" | .hd_line = "" else . end)
      elif ($c == ";" or $c == "&" or $c == "|" or $c == ")") then tok_sep($c)
      else .lit += $c | .started = true
      end
    )
    | .prev = $c
  )
  # A script may end without a trailing newline: close a final heredoc whose last
  # line is its delimiter, and accept a comment that runs to the end of the text.
  | (if .mode == "heredoc"
       and ((if .hd_queue[0].strip then (.hd_line | sub("^\t+"; "")) else .hd_line end) == .hd_queue[0].delim)
     then .hd_queue = .hd_queue[1:] | (if (.hd_queue | length) == 0 then .mode = "code" else . end)
     else . end)
  | tok_push
  | { words: .out,
      risky: (.risky
              or (.mode == "single") or (.mode == "double") or (.mode == "backtick")
              or ((.hd_queue | length) > 0) or (.hd_want != 0)) };

# Split the word stream into simple commands, dropping the two groups that only
# look like commands:
#
#   array literals   'args=(nix develop)' assigns two strings and runs nothing.
#   case patterns    a group closed by a ')' that opened nothing is a pattern,
#                    so the 'nix-build)' of a case branch is data while the
#                    branch body after it is a real command.
def group_commands:
  reduce .[] as $t (
    { cmds: [], cur: [], skip: false, depth: 0, risky: false };
    if ($t.sep // null) != null then
      (if .skip then
         (if $t.sep == ")" then .skip = false else .risky = (.risky or ($t.sep == "(")) end)
       elif $t.sep == "(" then .cmds += [.cur] | .depth += 1
       elif $t.sep == ")" then
         (if .depth > 0 then .cmds += [.cur] | .depth -= 1 else . end)
       else .cmds += [.cur]
       end)
      | .cur = []
    else
      (if .skip then .
       elif ((.cur | length) == 0) and $t.ok and ($t.lit | test("^[A-Za-z_][A-Za-z0-9_]*(\\[[^]]*\\])?\\+?=\\("))
       then .skip = true
       else .cur += [$t] end)
    end
  )
  | { cmds: (.cmds + [.cur]), risky: .risky };

def is_nix_name($w): $w.ok and ((nix_command_names | index($w.lit)) != null);
def is_nix_subcommand($w): $w.ok and ((nix_subcommands | index($w.lit)) != null);
# A Nix command name anywhere in an argument, on its own token boundary — the
# form './runner.sh "nix develop"' and awk's system("nix develop") both take.
def mentions_nix_token: any(. as $e | $e.ok and ($e.lit | test(nix_token_pattern)));

# One simple command -> "nix" | "plain" | "ambiguous" | {recurse: <script>}.
def cmd_verdict:
  if length == 0 then "plain"
  else
    .[0] as $w | .[1:] as $rest
    | if ($w.ok | not) then "ambiguous"
      elif ($w.lit | test("^[0-9]*[<>]")) then
        (if ($w.lit | test("^[0-9]*[<>]+$")) then ($rest[1:] | cmd_verdict) else ($rest | cmd_verdict) end)
      elif ($w.lit | test("^[A-Za-z_][A-Za-z0-9_]*(\\[[^]]*\\])?\\+?=")) then ($rest | cmd_verdict)
      elif (shell_keywords | index($w.lit)) != null then ($rest | cmd_verdict)
      elif $w.lit == "nix" then
        # 'nix' is a multiplexer, and only the FIRST argument decides what it
        # does: 'nix --version develop' prints the version, and a supported word
        # later in the tail proves nothing. An option before the subcommand is
        # unreadable rather than assumed, because option arity is unknown, and an
        # unrecognised subcommand is unreadable rather than assumed inert,
        # because 'nix eval' and friends do read the store.
        (if ($rest | length) == 0 then "plain"
         elif is_nix_subcommand($rest[0]) then "nix"
         else "ambiguous" end)
      elif (nix_legacy_commands | index($w.lit)) != null then "nix"
      elif (command_wrappers | index($w.lit)) != null then
        # 'sudo nix build' is readable; 'sudo -u root nix build' is not, because
        # which word is the command depends on what the option consumes.
        (if ($rest | length) == 0 then "plain"
         elif ($rest[0].ok | not) or ($rest[0].lit | test("^-")) then "ambiguous"
         else ($rest | cmd_verdict) end)
      elif (shell_interpreters | index($w.lit)) != null then
        # The script of a -c flag is read as a script. Combined flags count:
        # 'bash -lc <script>' is as much a nested shell as 'bash -c <script>'.
        ([$rest | to_entries[] | select(.value.ok and (.value.lit | test("^-[A-Za-z]*c[A-Za-z]*$"))) | .key] | first) as $i
        | (if $i == null then (if ($rest | mentions_nix_token) then "ambiguous" else "plain" end)
           elif ($rest | length) <= ($i + 1) then "ambiguous"
           elif ($rest[$i + 1].ok | not) then "ambiguous"
           else { recurse: $rest[$i + 1].lit }
           end)
      elif $w.lit == "eval" then "ambiguous"
      elif ($rest | mentions_nix_token) then
        (if (inert_commands | index($w.lit)) != null then "plain" else "ambiguous" end)
      else "plain"
      end
  end;

# 'nix() { … }', 'function nix …', 'alias nix=…' and 'alias helper="nix develop"'
# all change what some later word runs, so no invocation in the script is
# evidence of store use any more. An ordinary assignment is not an alias: in
# 'FOO=nix nix develop', the first word sets an environment variable and the
# second word still invokes Nix.
def alias_hides_nix:
  group_commands as $groups
  | any(
      $groups.cmds[];
      . as $cmd
      | (($cmd[0].ok? // false) and ($cmd[0].lit == "alias"))
        and any(
          $cmd[1:][];
          (.ok? // false)
            and (.lit | test("^[A-Za-z_][A-Za-z0-9_-]*="))
            and ((.lit | test("^[A-Za-z_][A-Za-z0-9_]*(\\[[^]]*\\])?\\+?=\\(")) | not)
            and (.lit | test(nix_token_pattern))
        )
    );

def hides_nix:
  . as $ts
  | (alias_hides_nix) as $alias_hides
  | if $alias_hides then true
    else
      [range(0; ($ts | length))]
      | any(
          . as $i
          | ($ts[$i]) as $w
          | ($ts[$i + 1]) as $n
          | ($w.ok // false)
            and (
              ($w.lit | test("^(nix|nix-build|nix-shell|nix-store)\\("))
              or (is_nix_name($w) and (($n.sep? // "") == "("))
              or (($w.lit == "function") and (($n.ok? // false) and is_nix_name($n)))
            )
        )
    end;

# Any function definition, by either spelling. Whether such a function is ever
# called is beyond a lexer, so a definition plus a Nix invocation anywhere in the
# script is unreadable rather than proof that Nix runs.
def defines_function:
  . as $ts
  | [range(0; ($ts | length))]
  | any(
      . as $i
      | ($ts[$i]) as $w
      | ($ts[$i + 1]) as $n
      | ($ts[$i + 2]) as $n2
      | ($w.ok // false)
        and (
          ($w.lit | test("^[A-Za-z_][A-Za-z0-9_.-]*\\(\\)?$"))
          or ($w.lit == "function")
          or (($w.lit | test("^[A-Za-z_][A-Za-z0-9_.-]*$"))
              and (($n.sep? // "") == "(") and (($n2.sep? // "") == ")"))
        )
    );

def run_verdict($depth):
  (shell_words) as $lex
  | ($lex.words | group_commands) as $g
  | [$g.cmds[] | cmd_verdict]
  | map(if type == "object" then (if $depth >= 3 then "ambiguous" else (.recurse | run_verdict($depth + 1)) end) else . end)
  | if ($lex.words | hides_nix) then "ambiguous"
    elif (index("nix") != null) then
      (if ($lex.words | defines_function) then "ambiguous" else "nix" end)
    elif $lex.risky or $g.risky or (index("ambiguous") != null) then "ambiguous"
    else "plain"
    end;

def run_verdict: run_verdict(0);
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
         then "nix-store-user"
         else
           ([($job.steps // [])[] | ((.run // "") | tostring) | run_verdict]) as $verdicts
           | if ($verdicts | index("nix")) != null then "nix-store-user"
             elif ($verdicts | index("ambiguous")) != null then "unreadable"
             else "no-nix"
             end
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
    # shellcheck disable=SC2016 # This is the literal GitHub expression opener.
    github_expression_open='${{'

    # S31 markers are human-authored review records. A GitHub expression is
    # resolved only at run time, so it does not state a reason in source.
    case "${fallback_reason}" in
    *"${github_expression_open}"*) echo "❌ ${file} job '${job}' must record S31_RUNNER_FALLBACK_REASON as literal text, not a GitHub expression" >&2 && exit 1 ;;
    esac
    case "${exempt_reason}" in
    *"${github_expression_open}"*) echo "❌ ${file} job '${job}' must record S31_CACHE_EXEMPT_REASON as literal text, not a GitHub expression" >&2 && exit 1 ;;
    esac

    venue_count=$((namespace_cache_primary + namespace_cache_fallback + namespace_bare_primary + namespace_bare_fallback + github_primary + github_fallback))
    [ "${venue_count}" -ne 1 ] && echo "❌ ${file} job '${job}' must select exactly one S31 primary or fallback venue label" >&2 && exit 1

    cache_capable=$((namespace_cache_primary + namespace_cache_fallback))
    namespace_venue=$((cache_capable + namespace_bare_primary + namespace_bare_fallback))

    # An unreadable job is refused on EVERY venue, and this is the reason the
    # classification has three answers instead of two. Treating "cannot tell" as
    # "not Nix" would be safe on a cache-capable venue and unsafe on the bare one:
    # there it would silently excuse a real Nix job from the cache labels AND from
    # env.S31_CACHE_EXEMPT_REASON, which is the very hole the exemption exists to
    # close. The gate therefore declines to guess, on any venue.
    if [ "${nix_use}" = "unreadable" ]; then
      unreadable_hint="an expanded or shadowed command name, a wrapper with options, eval, an unterminated quote or heredoc, or a nix command name handed to a command that may run it"
      if [ "${cache_capable}" -eq 1 ]; then
        echo "❌ ${file} job '${job}' claims the shared S31 Nix-store cache but is not a Nix-store user that this gate can confirm: its run: script uses shell syntax the gate cannot read as a command (${unreadable_hint}). Add the Nix setup action if it uses the Nix store, or write the command so it can be read" >&2
      else
        echo "❌ ${file} job '${job}' has a run: script whose Nix-store use cannot be determined (${unreadable_hint}): a job that uses the Nix store must declare it with the Nix setup action, or write the command so the gate can read it" >&2
      fi
      exit 1
    fi

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

if [ "${mode}" = "workflow-names" ]; then
  [ "$(yq -r '.name' .github/workflows/ci.yaml)" != "CI" ] && echo "❌ ci.yaml workflow name must be CI" >&2 && exit 1
  [ "$(yq -r '.name' .github/workflows/cd.yaml)" != "CD" ] && echo "❌ cd.yaml workflow name must be CD" >&2 && exit 1
  echo "✅ CI/CD workflow names conform"
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
