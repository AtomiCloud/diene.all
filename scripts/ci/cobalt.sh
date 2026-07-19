#!/usr/bin/env bash
set -euo pipefail

bash ./scripts/ci/setup.sh
bash ./scripts/validate/cobalt.sh schema
bash ./scripts/validate/cobalt.sh schema-drift
bash ./scripts/validate/cobalt.sh lint
bash ./scripts/validate/cobalt.sh render
bash ./scripts/validate/cobalt.sh store
bash ./scripts/validate/cobalt.sh store-credential-negative
bash ./scripts/validate/cobalt.sh store-scope-negative
bash ./scripts/validate/cobalt.sh v1beta1-negative
bash ./scripts/validate/cobalt.sh crd-lifecycle-negative
bash ./scripts/validate/cobalt.sh fullname
bash ./scripts/validate/cobalt.sh labels
bash ./scripts/validate/cobalt.sh rendered-manifests
bash ./scripts/validate/cobalt.sh vap-latest-negative
bash ./scripts/validate/cobalt.sh publish-git
bash ./scripts/validate/cobalt.sh publish-oci
bash ./scripts/validate/cobalt.sh version
bash ./scripts/validate/cobalt.sh presence
bash ./scripts/validate/gitlint-types.sh

echo "✅ Cobalt CI validation complete"
