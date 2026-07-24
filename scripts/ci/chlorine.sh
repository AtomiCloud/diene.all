#!/usr/bin/env bash
# ### chlorine-ci
# #### source: chlorine
#
# Runs the complete chlorine unit/static testing pyramid. The k3d integration
# tier (secret-change → pod-restart) is a serialized live proof and lives in
# scripts/validate/chlorine-k3d.sh.
set -euo pipefail

bash ./scripts/ci/setup.sh
bash ./scripts/validate/chlorine.sh schema
bash ./scripts/validate/chlorine.sh schema-drift
bash ./scripts/validate/chlorine.sh lint
bash ./scripts/validate/chlorine.sh render
bash ./scripts/validate/chlorine.sh labels
bash ./scripts/validate/chlorine.sh labels-violation
bash ./scripts/validate/chlorine.sh reloader
bash ./scripts/validate/chlorine.sh reloader-violation
bash ./scripts/validate/chlorine.sh fullname
bash ./scripts/validate/chlorine.sh fullname-violation
bash ./scripts/validate/chlorine.sh fullname-sa-violation
bash ./scripts/validate/chlorine.sh rendered-manifests
bash ./scripts/validate/chlorine.sh vap-latest
bash ./scripts/validate/chlorine.sh schema-violation
bash ./scripts/validate/chlorine.sh publish-git
bash ./scripts/validate/chlorine.sh publish-oci
bash ./scripts/validate/chlorine.sh version-mismatch
bash ./scripts/validate/chlorine-k3d-contract.sh
bash ./scripts/validate/gitlint-types.sh

echo "✅ Chlorine unit/static pyramid complete"
