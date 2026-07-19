#!/usr/bin/env bash
# ### vanadium-ci
# #### source: vanadium
set -euo pipefail

bash ./scripts/validate/vanadium.sh schema
bash ./scripts/validate/vanadium.sh schema-drift
bash ./scripts/validate/vanadium.sh lint
bash ./scripts/validate/vanadium.sh render
bash ./scripts/validate/vanadium.sh labels
bash ./scripts/validate/vanadium.sh fullname
bash ./scripts/validate/vanadium.sh exemption
bash ./scripts/validate/vanadium.sh audit-enforce
bash ./scripts/validate/vanadium.sh conformance
bash ./scripts/validate/vanadium.sh publish-git
bash ./scripts/validate/vanadium.sh publish-oci
bash ./scripts/validate/vanadium.sh version
bash ./scripts/validate/vanadium.sh parity
bash ./scripts/validate/gitlint-types.sh

echo "✅ Vanadium CI validation complete"
