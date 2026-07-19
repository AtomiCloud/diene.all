#!/usr/bin/env bash
set -euo pipefail

# Three-layer boundary gate: the pure domain layer (lib/operator/**) must never
# import Kubernetes packages. A business rule that reaches for a k8s type belongs
# in an adapter, not the domain; injecting such an import reddens this gate.

fail() {
  echo "❌ operator architecture: $1" >&2
  exit 1
}

if grep -rnE '"(k8s\.io|sigs\.k8s\.io)/' lib/operator; then
  fail "lib/operator must not import k8s.io/* or sigs.k8s.io/* (keep the domain layer pure)"
fi

echo "✅ operator architecture boundary passed"
