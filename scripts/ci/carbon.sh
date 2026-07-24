#!/usr/bin/env bash
set -euo pipefail

offline="${1:-}"
[ -z "${offline}" ] || [ "${offline}" = "--offline" ] || {
  echo "❌ unsupported Carbon CI option '${offline}'" >&2
  exit 1
}

bash scripts/ci/setup.sh
[ "${offline}" = "--offline" ] || bun install --cwd cyan --frozen-lockfile
bash scripts/validate/carbon.sh schema
bash scripts/validate/carbon.sh schema-drift
bash scripts/validate/carbon.sh lint
bash scripts/validate/carbon.sh render
bash scripts/validate/carbon.sh render-contract
bash scripts/validate/carbon.sh namespace-negative
bash scripts/validate/carbon.sh dependency-missing-negative
bash scripts/validate/carbon.sh dependency-conflict-negative
bash scripts/validate/carbon.sh folder-mapping-negative
bash scripts/validate/carbon.sh garden
bash scripts/validate/carbon.sh garden-store-negative
bash scripts/validate/carbon.sh labels
bash scripts/validate/carbon.sh rendered-manifests
bash scripts/validate/carbon.sh vap-wiring-negative
bash scripts/validate/carbon.sh cyan-offline
if [ "${offline}" = "--offline" ]; then
  bash scripts/validate/carbon.sh scaffold-offline
else
  bash scripts/validate/carbon.sh platform-schema
  bash scripts/validate/carbon.sh scaffold
fi
bash scripts/validate/carbon.sh workflow-source
bash scripts/validate/carbon.sh workflow-filter
bash scripts/validate/carbon.sh workflow-name
bash scripts/validate/carbon.sh workflow-concurrency
bash scripts/validate/carbon.sh static
bash scripts/validate/carbon.sh publish-git
bash scripts/validate/carbon.sh publish-oci
bash scripts/validate/carbon.sh presence
bash scripts/validate/carbon-k3d-contract.sh
bash scripts/validate/gitlint-types.sh

echo "✅ Carbon CI validation complete"
