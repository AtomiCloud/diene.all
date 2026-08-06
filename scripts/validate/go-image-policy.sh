#!/usr/bin/env bash
set -euo pipefail

policy="${1:-}"
[ -z "${policy}" ] && echo "❌ image policy not set" >&2 && exit 1

dockerfile="infra/Dockerfile"
[ ! -f "${dockerfile}" ] && echo "❌ '${dockerfile}' not found" >&2 && exit 1

# Read stages the way Docker does: keywords are case-insensitive and indentable, --flags are noise, and an uninterpretable shape is a parse failure rather than a skipped line.
reader_status=0
instructions="$(awk -v OFS='\t' '
  { keyword = toupper($1) }
  keyword ~ /^#/ { next }
  keyword != "FROM" && keyword != "USER" { next }
  { gsub(/[[:space:]]--[^[:space:]]+/, "") }
  NF < 2 { print "PARSE", FNR; exit }
  keyword == "USER" && NF > 2 { print "PARSE", FNR; exit }
  keyword == "USER" { print keyword, $2; next }
  NF == 2 { print keyword, $2; next }
  NF == 4 && toupper($3) == "AS" { print keyword, $2 " AS " $4; next }
  { print "PARSE", FNR; exit }
' "${dockerfile}" 2>&1)" || reader_status=$?
[ "${reader_status}" -ne 0 ] && echo "❌ could not read '${dockerfile}' image stages: ${instructions}" >&2 && exit 1

parse_line="$(awk -F '\t' '$1 == "PARSE" {print $2; exit}' <<<"${instructions}")"
[ -n "${parse_line}" ] && echo "❌ could not parse '${dockerfile}' image instruction on line ${parse_line}" >&2 && exit 1

# Read policy from the shipped final stage so an earlier compliant stage cannot vouch for a later unsafe one.
final_from="$(awk -F '\t' '$1 == "FROM" {stage = $2} END {print stage}' <<<"${instructions}")"
[ -z "${final_from}" ] && echo "❌ '${dockerfile}' declares no image stage" >&2 && exit 1

# Every stage starts unprivileged again, and within the final stage the last USER wins.
final_user="$(awk -F '\t' '$1 == "FROM" {user = ""} $1 == "USER" {user = $2} END {print user}' <<<"${instructions}")"
observed_user="$([ -n "${final_user}" ] && echo "USER ${final_user}" || echo '<none declared>')"

# Keep the violated-rule phrase stable because sabotage probes assert it.
declare -A diagnostics=([distroless]='final runtime image must use the distroless nonroot base' [nonroot]='final runtime image must run as 65532:65532')
declare -A subjects=([distroless]='final stage base image' [nonroot]='final stage effective user')
declare -A observations=([distroless]="FROM ${final_from}" [nonroot]="${observed_user}")
declare -A expectations=([distroless]='FROM gcr.io/distroless/static-debian12:nonroot AS runtime' [nonroot]='USER 65532:65532')
diagnostic="${diagnostics[${policy}]:-}"
[ -z "${diagnostic}" ] && echo "❌ unknown image policy '${policy}'" >&2 && exit 1
subject="${subjects[${policy}]}"
observed="${observations[${policy}]}"
expected="${expectations[${policy}]}"

[ "${observed}" != "${expected}" ] && echo "❌ ${diagnostic}: ${subject} is '${observed}', expected '${expected}'" >&2 && exit 1

echo "✅ ${policy} image policy passed"
