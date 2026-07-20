#!/usr/bin/env bash
set -euo pipefail

bash ./scripts/ci/setup.sh
bash ./scripts/validate/zinc.sh schema
bash ./scripts/validate/zinc.sh schema-drift
bash ./scripts/validate/zinc.sh lint
bash ./scripts/validate/zinc.sh render
bash ./scripts/validate/zinc.sh lpsm-labels
bash ./scripts/validate/zinc.sh directory-map
bash ./scripts/validate/zinc.sh entei-overlay
bash ./scripts/validate/zinc.sh issuer-cardinality
bash ./scripts/validate/zinc.sh no-certificate
bash ./scripts/validate/zinc.sh external-secret
bash ./scripts/validate/zinc.sh rendered-manifests
bash ./scripts/validate/zinc.sh task-surface
bash ./scripts/validate/zinc.sh k3d-guard
bash ./scripts/validate/zinc.sh publish-git
bash ./scripts/validate/zinc.sh publish-oci
bash ./scripts/validate/zinc.sh version
bash ./scripts/validate/zinc.sh presence
bash ./scripts/validate/gitlint-types.sh

echo "✅ zinc CI validation complete"
