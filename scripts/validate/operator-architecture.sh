#!/usr/bin/env bash
set -euo pipefail

# tools/archcheck is AST-aware, so it catches a leaked decision whatever it imports.

echo "🔎 checking operator layer imports"

k8s_in_domain="$(grep -rnE '"(k8s\.io|sigs\.k8s\.io)/' lib/operator || true)"
[ -n "${k8s_in_domain}" ] && echo "${k8s_in_domain}" >&2 && echo "❌ operator architecture: lib/operator must not import k8s.io/* or sigs.k8s.io/* (keep the domain layer pure)" >&2 && exit 1

domain_in_controllers="$(grep -rnE '"github\.com/AtomiCloud/diene\.go-base/lib/operator/(note|plan|brake)"' adapters/operator/controllers || true)"
[ -n "${domain_in_controllers}" ] && echo "${domain_in_controllers}" >&2 && echo "❌ operator architecture: controllers must not import lib/operator/{note,plan,brake}; route domain decisions through lib/operator/reconcile" >&2 && exit 1

echo "🧪 asserting controllers delegate reconcile decisions to lib/operator/reconcile"

go run ./tools/archcheck

echo "✅ operator architecture boundary passed"
