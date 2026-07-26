#!/usr/bin/env bash
set -euo pipefail

# tools/archcheck is AST-aware, so it catches a leaked decision whatever it imports.

echo "🔎 checking operator layer imports"

# Read the module path from go.mod instead of hard-coding it: a stale literal would
# silently stop matching and make the forbidden-import grep below pass vacuously.
module="$(go list -m)"
[ -z "${module}" ] && echo "❌ operator architecture: go.mod declares no main module path" >&2 && exit 1
echo "📦 module import root: ${module}"

# Sentinel: controllers MUST import the reconcile facade. This proves the interpolated
# prefix really matches this tree, so a wrong module path fails closed instead of green.
delegation="$(grep -rlF "\"${module}/lib/operator/reconcile\"" adapters/operator/controllers || true)"
[ -z "${delegation}" ] && echo "❌ operator architecture: no controller imports \"${module}/lib/operator/reconcile\" — the module path is wrong or delegation was removed, which would make the layering greps below vacuous" >&2 && exit 1
echo "🔗 reconcile facade imported by: $(printf '%s' "${delegation}" | tr '\n' ' ')"

k8s_in_domain="$(grep -rnE '"(k8s\.io|sigs\.k8s\.io)/' lib/operator || true)"
[ -n "${k8s_in_domain}" ] && echo "${k8s_in_domain}" >&2 && echo "❌ operator architecture: lib/operator must not import k8s.io/* or sigs.k8s.io/* (keep the domain layer pure)" >&2 && exit 1

domain_in_controllers="$(grep -rnE "\"${module//./\\.}/lib/operator/(note|plan|brake)\"" adapters/operator/controllers || true)"
[ -n "${domain_in_controllers}" ] && echo "${domain_in_controllers}" >&2 && echo "❌ operator architecture: controllers must not import lib/operator/{note,plan,brake}; route domain decisions through lib/operator/reconcile" >&2 && exit 1

echo "🧪 asserting controllers delegate reconcile decisions to lib/operator/reconcile"

go run ./tools/archcheck

echo "✅ operator architecture boundary passed"
