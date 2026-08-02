#!/usr/bin/env bash
set -euo pipefail

policy="${1:-}"
[ -z "${policy}" ] && echo "❌ image policy not set" >&2 && exit 1

dockerfile="infra/Dockerfile"
[ ! -f "${dockerfile}" ] && echo "❌ '${dockerfile}' not found" >&2 && exit 1

# Read policy from the shipped final stage so an earlier compliant stage cannot vouch for a later unsafe one.
final_from_line="$(rg -n '^FROM ' "${dockerfile}" | tail -n 1 | cut -d ':' -f 1 || true)"
[ -z "${final_from_line}" ] && echo "❌ '${dockerfile}' declares no image stage" >&2 && exit 1

final_from="$(sed -n "${final_from_line}p" "${dockerfile}")"

# A final stage's last USER is effective because later instructions override earlier ones.
final_user="$(tail -n "+${final_from_line}" "${dockerfile}" | rg '^USER ' | tail -n 1 || true)"

# Keep the violated-rule phrase stable because sabotage probes assert it.
case "${policy}" in
distroless)
  diagnostic="final runtime image must use the distroless nonroot base"
  subject="final stage base image"
  observed="${final_from}"
  expected="FROM gcr.io/distroless/static-debian12:nonroot AS runtime"
  ;;
nonroot)
  diagnostic="final runtime image must run as 65532:65532"
  subject="final stage effective user"
  observed="${final_user:-<none declared>}"
  expected="USER 65532:65532"
  ;;
*)
  echo "❌ unknown image policy '${policy}'" >&2
  exit 1
  ;;
esac

[ "${observed}" != "${expected}" ] && echo "❌ ${diagnostic}: ${subject} is '${observed}', expected '${expected}'" >&2 && exit 1

echo "✅ ${policy} image policy passed"
