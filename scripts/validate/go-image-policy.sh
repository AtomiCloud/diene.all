#!/usr/bin/env bash
set -euo pipefail

policy="${1:-}"
[ -z "${policy}" ] && echo "❌ image policy not set" >&2 && exit 1

case "${policy}" in
distroless)
  tail -n +1 infra/Dockerfile | rg '^FROM gcr\.io/distroless/static-debian12:nonroot AS runtime$' >/dev/null
  ;;
nonroot)
  tail -n +1 infra/Dockerfile | rg '^USER 65532:65532$' >/dev/null
  ;;
*)
  echo "❌ unknown image policy '${policy}'" >&2
  exit 1
  ;;
esac

echo "✅ ${policy} image policy passed"
