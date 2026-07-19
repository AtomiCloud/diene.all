#!/usr/bin/env bash
# Stacked sulfur render/install wrapper — the single supported route behind the
# public `example:*` cluster Taskfile (debug/template/install).
#
# Subchart values cannot call templates, so the mandatory LPSM identity layer
# (upstream.global.commonLabels, enforced by chart/templates/validate.yaml) is
# generated from the single labelPrefix (+ serviceTree) by
# scripts/local/gen-identity-values.sh. Every render/install route MUST append
# that generated layer as its FINAL --values argument, derived from the SAME
# base+landscape+cluster stack it renders, or rendering fails closed. This wrapper
# always runs the generator from the repository root (its base is chart/values.yaml),
# appends the layer last, and removes only its own temporary layer. The vendored
# cert-manager archive is the source of truth, so no dependency rebuild is needed.
#
# Usage:
#   render-stacked.sh <debug|template|install> <release> <namespace> \
#     <landscape-values> <cluster-values> [extra helm args...]
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

# Run from the repository root so the generator resolves its chart/values.yaml base
# and the overlay paths regardless of the caller's working directory (the Taskfile
# no longer needs `dir: chart`, which broke the config vendor and the generator).
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

# Diagnostics go to stderr; stdout carries only the rendered manifest for `template`
# and `debug`, so callers (and the Taskfile-surface regression) can parse it.
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

echo "📝 Vendoring external config" >&2
./scripts/local/vendor-chart-config.sh >&2

echo "📝 Generating the LPSM identity layer from the base+landscape+cluster stack" >&2
identity="${tmp}/identity.yaml"
./scripts/local/gen-identity-values.sh "${landscape_values}" "${cluster_values}" >"${identity}"

echo "🔨 Rendering the stacked chart (${mode})" >&2
case "${mode}" in
debug)
  helm template "${release}" chart --namespace "${namespace}" --debug \
    --values "${landscape_values}" --values "${cluster_values}" --values "${identity}" "$@"
  ;;
template)
  helm template "${release}" chart --namespace "${namespace}" \
    --values "${landscape_values}" --values "${cluster_values}" --values "${identity}" "$@"
  ;;
install)
  helm upgrade --install "${release}" chart --namespace "${namespace}" --create-namespace \
    --values "${landscape_values}" --values "${cluster_values}" --values "${identity}" \
    --wait --timeout 5m "$@"
  ;;
*)
  echo "❌ unknown render mode '${mode}'" >&2
  exit 1
  ;;
esac
