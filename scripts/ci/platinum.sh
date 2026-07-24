#!/usr/bin/env bash
set -euo pipefail

bash ./scripts/ci/setup.sh
bash ./scripts/validate/platinum.sh schema
bash ./scripts/validate/platinum.sh schema-drift
bash ./scripts/validate/platinum.sh lint
bash ./scripts/validate/platinum.sh render
bash ./scripts/validate/platinum.sh labels
bash ./scripts/validate/platinum.sh reloader
bash ./scripts/validate/platinum.sh fullname
bash ./scripts/validate/platinum.sh gateway-class
bash ./scripts/validate/platinum.sh gateway-proxy
bash ./scripts/validate/platinum.sh gateway-health
bash ./scripts/validate/platinum.sh registered-cert
bash ./scripts/validate/platinum.sh entei-overlay
bash ./scripts/validate/platinum.sh lb
bash ./scripts/validate/platinum.sh task-surface
bash ./scripts/validate/platinum.sh rendered-manifests
bash ./scripts/validate/platinum.sh vap-sabotage
bash ./scripts/validate/platinum.sh publish-git
bash ./scripts/validate/platinum.sh publish-oci
bash ./scripts/validate/platinum.sh version
bash ./scripts/validate/platinum.sh presence
bash ./scripts/validate/platinum.sh tokenization-presence
bash ./scripts/validate/platinum.sh gateway-api-crd-fixture
bash ./scripts/validate/gitlint-types.sh

echo "✅ Platinum CI validation complete"
