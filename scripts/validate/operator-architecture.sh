#!/usr/bin/env bash
set -euo pipefail

# Three-layer boundary gate.
#
# Primary (positive, AST-aware): the controllers package must delegate reconcile
# decisions to the pure lib/operator/reconcile service and contain no inline
# business decision — enforced by tools/archcheck regardless of which packages a
# leaked decision imports.
#
# Secondary (import denylists): the pure domain layer imports no Kubernetes, and
# controllers do not import the domain decision packages directly.

fail() {
  echo "❌ operator architecture: $1" >&2
  exit 1
}

if grep -rnE '"(k8s\.io|sigs\.k8s\.io)/' lib/operator; then
  fail "lib/operator must not import k8s.io/* or sigs.k8s.io/* (keep the domain layer pure)"
fi

if grep -rnE '"github\.com/AtomiCloud/diene\.go-base/lib/operator/(note|plan|brake)"' adapters/operator/controllers; then
  fail "controllers must not import lib/operator/{note,plan,brake}; route domain decisions through lib/operator/reconcile"
fi

go run ./tools/archcheck

echo "✅ operator architecture boundary passed"
