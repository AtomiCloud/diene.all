#!/usr/bin/env bash
set -euo pipefail

bash ./scripts/ci/setup.sh
bash ./scripts/validate/sulfur.sh schema
bash ./scripts/validate/sulfur.sh schema-negative
bash ./scripts/validate/sulfur.sh schema-drift
bash ./scripts/validate/sulfur.sh dependency
bash ./scripts/validate/sulfur.sh upstream
bash ./scripts/validate/sulfur.sh lint
bash ./scripts/validate/sulfur.sh render
bash ./scripts/validate/sulfur.sh labels
bash ./scripts/validate/sulfur.sh reloader
bash ./scripts/validate/sulfur.sh gateway-api
bash ./scripts/validate/sulfur.sh dead-flag
bash ./scripts/validate/sulfur.sh issuer-boundary
bash ./scripts/validate/sulfur.sh crds
bash ./scripts/validate/sulfur.sh sequential-minor
bash ./scripts/validate/sulfur.sh rendered-manifests
bash ./scripts/validate/sulfur.sh vap-sabotage
bash ./scripts/validate/sulfur.sh publish-git
bash ./scripts/validate/sulfur.sh publish-oci
bash ./scripts/validate/sulfur.sh version
bash ./scripts/validate/sulfur.sh presence
bash ./scripts/validate/release-config.sh all
bash ./scripts/validate/gitlint-types.sh

echo "✅ Sulfur CI validation complete"
