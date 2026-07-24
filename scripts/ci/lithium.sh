#!/usr/bin/env bash
set -euo pipefail

option="${1:-}"
[ -z "${option}" ] || [ "${option}" = "--offline" ] || {
  echo "❌ unsupported Lithium CI option ${option}" >&2
  exit 1
}
bash scripts/ci/setup.sh
bash scripts/validate/lithium.sh all
if [ "${option}" != --offline ]; then
  bash scripts/validate/lithium.sh filter-runtime
  bash scripts/validate/lithium-bootstrap-runtime.sh
fi
bash scripts/validate/lithium-k3d-contract.sh
bash scripts/validate/gitlint-types.sh
echo "✅ Lithium CI validation complete"
