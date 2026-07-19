#!/usr/bin/env bash
set -euo pipefail

# CRD-drift gate: regenerate the CRDs and deepcopy from the Go types + markers and
# assert the committed artifacts are in sync. Editing an API type without
# regenerating reddens this gate.

fail() {
  echo "❌ operator CRD drift: $1" >&2
  exit 1
}

crd_dir="infra/root_chart/templates/crds"

controller-gen crd paths=./api/... output:crd:dir="${crd_dir}"
controller-gen object paths=./api/...

if ! git diff --quiet -- "${crd_dir}" api/v1alpha1/zz_generated.deepcopy.go; then
  git --no-pager diff -- "${crd_dir}" api/v1alpha1/zz_generated.deepcopy.go >&2
  fail "generated CRDs/deepcopy differ from committed — run scripts/local/operator-manifests.sh"
fi

echo "✅ operator CRD drift check passed"
