#!/usr/bin/env bash
set -euo pipefail

bash ./scripts/ci/setup.sh
bash ./scripts/validate/garden-parity.sh schema
bash ./scripts/validate/garden-parity.sh profile-enum
bash ./scripts/validate/garden-parity.sh no-duplicate-roster
bash ./scripts/validate/garden-parity.sh union-duplicate-negative
bash ./scripts/validate/garden-parity.sh hosted-filter
bash ./scripts/validate/garden-parity.sh local-profile-edge
bash ./scripts/validate/garden-parity.sh filter-drift-negative
bash ./scripts/validate/garden-parity.sh doctor
bash ./scripts/validate/garden-parity.sh doctor-installed
bash ./scripts/validate/garden-parity.sh doctor-installed-negative
bash ./scripts/validate/garden-parity.sh doctor-unexplained-negative
bash ./scripts/validate/garden-parity.sh pins
bash ./scripts/validate/garden-parity.sh vcluster-lock
bash ./scripts/validate/garden-parity.sh vcluster-lock-negative
bash ./scripts/validate/garden-parity.sh fixture-fence
bash ./scripts/validate/garden-parity.sh presence

echo "✅ Garden parity CI validation complete"
