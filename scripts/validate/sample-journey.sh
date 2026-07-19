#!/usr/bin/env bash
set -euo pipefail

# Manager runtime journey: build the composition root and prove the packaged
# manager binary runs and reports its controller/observe interface. The full
# health-endpoint + toy-CR reconcile journey against a live cluster is the
# k3d-install-toy-reconcile smoke (scripts/local/operator-e2e.sh).

./scripts/local/build.sh

output="$(./dist/manager --help 2>&1 || true)"
echo "${output}" | rg -q -- 'enable-note' || {
  echo "❌ manager runtime did not report its controller enable flags" >&2
  exit 1
}
echo "${output}" | rg -q -- 'observe' || {
  echo "❌ manager runtime did not report the observe flag" >&2
  exit 1
}

echo "✅ Manager runtime journey passed"
