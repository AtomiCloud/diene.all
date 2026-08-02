#!/usr/bin/env bash
set -euo pipefail

policy="${1:-}"
[ -z "${policy}" ] && echo "❌ image policy not set" >&2 && exit 1

dockerfile="infra/Dockerfile"
[ ! -f "${dockerfile}" ] && echo "❌ '${dockerfile}' not found" >&2 && exit 1

# Read policy from the shipped final stage so an earlier compliant stage cannot vouch for a later unsafe one.
reader_status=0
from_lines="$(rg -n '^FROM ' "${dockerfile}" 2>&1)" || reader_status=$?
[ "${reader_status}" -gt 1 ] && echo "❌ could not inspect '${dockerfile}' image stages: ${from_lines}" >&2 && exit 1
final_from_line="$(tail -n 1 <<<"${from_lines}" | cut -d ':' -f 1)"
[ -z "${final_from_line}" ] && echo "❌ '${dockerfile}' declares no image stage" >&2 && exit 1

final_from="$(sed -n "${final_from_line}p" "${dockerfile}")"

# A final stage's last USER is effective because later instructions override earlier ones.
final_user="$(tail -n "+${final_from_line}" "${dockerfile}" | rg '^USER ' | tail -n 1 || true)"

# Keep the violated-rule phrase stable because sabotage probes assert it.
declare -A diagnostics=([distroless]='final runtime image must use the distroless nonroot base' [nonroot]='final runtime image must run as 65532:65532')
declare -A subjects=([distroless]='final stage base image' [nonroot]='final stage effective user')
declare -A observations=([distroless]="${final_from}" [nonroot]="${final_user:-<none declared>}")
declare -A expectations=([distroless]='FROM gcr.io/distroless/static-debian12:nonroot AS runtime' [nonroot]='USER 65532:65532')
diagnostic="${diagnostics[${policy}]:-}"
[ -z "${diagnostic}" ] && echo "❌ unknown image policy '${policy}'" >&2 && exit 1
subject="${subjects[${policy}]}"
observed="${observations[${policy}]}"
expected="${expectations[${policy}]}"

[ "${observed}" != "${expected}" ] && echo "❌ ${diagnostic}: ${subject} is '${observed}', expected '${expected}'" >&2 && exit 1

echo "✅ ${policy} image policy passed"
