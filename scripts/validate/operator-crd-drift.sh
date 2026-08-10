#!/usr/bin/env bash
set -euo pipefail

# Regeneration overwrites the working tree, so any remaining diff is real committed drift.

crd_dir="infra/root_chart/templates/crds"

echo "🔨 regenerating CRDs and deepcopy from ./api"

controller-gen crd paths=./api/... output:crd:dir="${crd_dir}"
controller-gen object paths=./api/...

drift="$(git --no-pager diff -- "${crd_dir}" api/v1alpha1/zz_generated.deepcopy.go || true)"
[ -n "${drift}" ] && echo "${drift}" >&2 && echo "❌ operator CRD drift: generated CRDs/deepcopy differ from committed — run scripts/local/operator-manifests.sh" >&2 && exit 1

echo "✅ operator CRD drift check passed"
