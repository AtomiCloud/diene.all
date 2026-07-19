#!/usr/bin/env bash
# ### aluminium-ci
# #### source: aluminium
# Runs the complete aluminium unit/static tier (S30 testing pyramid).
set -euo pipefail

bash ./scripts/ci/setup.sh
bash ./scripts/validate/aluminium.sh schema
bash ./scripts/validate/aluminium.sh schema-drift
bash ./scripts/validate/aluminium.sh lint
bash ./scripts/validate/aluminium.sh render
bash ./scripts/validate/aluminium.sh topology
bash ./scripts/validate/aluminium.sh otlp-contract
bash ./scripts/validate/aluminium.sh features-off
bash ./scripts/validate/aluminium.sh gigapipe-naming
bash ./scripts/validate/aluminium.sh secret
bash ./scripts/validate/aluminium.sh otlp-everywhere
bash ./scripts/validate/aluminium.sh lpsm-labels
bash ./scripts/validate/aluminium.sh rendered-manifests
bash ./scripts/validate/aluminium.sh latest-semver
bash ./scripts/validate/aluminium.sh kubeconfig-isolation
bash ./scripts/validate/aluminium.sh publish-git
bash ./scripts/validate/aluminium.sh publish-oci
bash ./scripts/validate/aluminium.sh version
bash ./scripts/validate/aluminium.sh presence
bash ./scripts/validate/gitlint-types.sh

echo "✅ aluminium CI validation complete"
