#!/usr/bin/env bash
set -euo pipefail

bash ./scripts/ci/setup.sh
bash ./scripts/validate/zinc.sh schema
bash ./scripts/validate/zinc.sh schema-negative
bash ./scripts/validate/zinc.sh schema-drift
bash ./scripts/validate/zinc.sh lint
bash ./scripts/validate/zinc.sh render
bash ./scripts/validate/zinc.sh labels
bash ./scripts/validate/zinc.sh le-directory-map
bash ./scripts/validate/zinc.sh issuer-cardinality
bash ./scripts/validate/zinc.sh entei-overlay
bash ./scripts/validate/zinc.sh no-certificate
bash ./scripts/validate/zinc.sh credential-literal
bash ./scripts/validate/zinc.sh rendered-manifests
bash ./scripts/validate/zinc.sh vap-sabotage
bash ./scripts/validate/zinc.sh publish-git
bash ./scripts/validate/zinc.sh publish-oci
bash ./scripts/validate/zinc.sh version
bash ./scripts/validate/zinc.sh presence
bash ./scripts/validate/release-config.sh all
bash ./scripts/validate/gitlint-types.sh

echo "✅ Zinc CI validation complete"
