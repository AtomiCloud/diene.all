#!/usr/bin/env bash
set -euo pipefail

bash ./scripts/ci/setup.sh
bash ./scripts/validate/chlorine.sh schema
bash ./scripts/validate/chlorine.sh schema-negative
bash ./scripts/validate/chlorine.sh schema-drift
bash ./scripts/validate/chlorine.sh dependency
bash ./scripts/validate/chlorine.sh upstream
bash ./scripts/validate/chlorine.sh lint
bash ./scripts/validate/chlorine.sh render
bash ./scripts/validate/chlorine.sh labels
bash ./scripts/validate/chlorine.sh reloader
bash ./scripts/validate/chlorine.sh auto-reload-all
bash ./scripts/validate/chlorine.sh fullname
bash ./scripts/validate/chlorine.sh rendered-manifests
bash ./scripts/validate/chlorine.sh vap-sabotage
bash ./scripts/validate/chlorine.sh publish-git
bash ./scripts/validate/chlorine.sh publish-oci
bash ./scripts/validate/chlorine.sh version
bash ./scripts/validate/chlorine.sh presence
bash ./scripts/validate/release-config.sh all
bash ./scripts/validate/gitlint-types.sh

echo "✅ Chlorine CI validation complete"
