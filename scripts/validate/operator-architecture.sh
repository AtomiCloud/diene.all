#!/usr/bin/env bash
set -euo pipefail

# Three-layer boundary gate:
#  1. The pure domain layer (lib/operator/**) must never import Kubernetes.
#  2. Controllers must stay thin: they may map API I/O and invoke the reconcile
#     application service, but must NOT import the domain decision internals
#     (lib/operator/{note,plan,brake}). Moving a business rule into a controller
#     pulls in one of those imports and reddens this gate.

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

echo "✅ operator architecture boundary passed"
