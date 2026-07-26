#!/usr/bin/env bash
set -euo pipefail

container="${OPERATOR_LEDGER_CONTAINER:-fleet-operator-ledger}"
docker rm -f "${container}" >/dev/null 2>&1 || true

echo "✅ Local MinIO ledger stopped"
