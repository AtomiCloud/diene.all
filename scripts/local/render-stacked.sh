#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
release="${2:-}"
namespace="${3:-}"
landscape_values="${4:-}"
cluster_values="${5:-}"
[ -z "${mode}" ] && echo "❌ render mode (debug|template|install) not set" >&2 && exit 1
[ -z "${release}" ] && echo "❌ release name not set" >&2 && exit 1
[ -z "${namespace}" ] && echo "❌ namespace not set" >&2 && exit 1
[ -z "${landscape_values}" ] && echo "❌ landscape values file not set" >&2 && exit 1
[ -z "${cluster_values}" ] && echo "❌ cluster values file not set" >&2 && exit 1
shift 5

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

case "${mode}" in
debug)
  helm template "${release}" chart --namespace "${namespace}" --debug --values "${landscape_values}" --values "${cluster_values}" "$@"
  ;;
template)
  helm template "${release}" chart --namespace "${namespace}" --values "${landscape_values}" --values "${cluster_values}" "$@"
  ;;
install)
  helm upgrade --install "${release}" chart --namespace "${namespace}" --create-namespace --values "${landscape_values}" --values "${cluster_values}" --wait --timeout 3m "$@"
  ;;
*)
  echo "❌ unknown render mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ zinc stacked ${mode} complete" >&2
