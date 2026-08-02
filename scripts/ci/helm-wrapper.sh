#!/usr/bin/env bash
set -euo pipefail

bash ./scripts/ci/setup.sh
bash ./scripts/validate/helm-wrapper.sh schema
bash ./scripts/validate/helm-wrapper.sh schema-drift
bash ./scripts/validate/helm-wrapper.sh lint
bash ./scripts/validate/helm-wrapper.sh render
bash ./scripts/validate/helm-wrapper.sh config-vendoring
bash ./scripts/validate/helm-wrapper.sh labels
bash ./scripts/validate/helm-wrapper.sh reloader
bash ./scripts/validate/helm-wrapper.sh secret
bash ./scripts/validate/helm-wrapper.sh fullname
bash ./scripts/validate/helm-wrapper.sh primordial
bash ./scripts/validate/helm-wrapper.sh lpsm
bash ./scripts/validate/helm-wrapper.sh lb
bash ./scripts/validate/helm-wrapper.sh task-surface
bash ./scripts/validate/helm-wrapper.sh rendered-manifests
bash ./scripts/validate/helm-wrapper.sh publish-git
bash ./scripts/validate/helm-wrapper.sh publish-oci
bash ./scripts/validate/helm-wrapper.sh version
bash ./scripts/validate/helm-wrapper.sh presence
bash ./scripts/validate/helm-wrapper.sh gateway-webhook-presence
bash ./scripts/validate/helm-wrapper.sh tokenization-presence
bash ./scripts/validate/gitlint-types.sh

echo "✅ Helm wrapper CI validation complete"
