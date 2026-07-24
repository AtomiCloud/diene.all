#!/usr/bin/env bash
set -euo pipefail

bash ./scripts/ci/setup.sh
bash ./scripts/validate/xenon.sh schema
bash ./scripts/validate/xenon.sh schema-negative
bash ./scripts/validate/xenon.sh schema-drift
bash ./scripts/validate/xenon.sh dependency
bash ./scripts/validate/xenon.sh upstream
bash ./scripts/validate/xenon.sh lint
bash ./scripts/validate/xenon.sh render
bash ./scripts/validate/xenon.sh labels
bash ./scripts/validate/xenon.sh reloader
bash ./scripts/validate/xenon.sh fullname
bash ./scripts/validate/xenon.sh task-surface
bash ./scripts/validate/xenon.sh sit-handoff
bash ./scripts/validate/xenon.sh toggle-map
bash ./scripts/validate/xenon.sh rendered-manifests
bash ./scripts/validate/xenon.sh vap-sabotage
bash ./scripts/validate/xenon.sh publish-git
bash ./scripts/validate/xenon.sh publish-oci
bash ./scripts/validate/xenon.sh version
bash ./scripts/validate/xenon.sh presence
bash ./scripts/validate/release-config.sh all
bash ./scripts/validate/gitlint-types.sh

echo "✅ Xenon CI validation complete"
