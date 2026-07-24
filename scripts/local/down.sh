#!/usr/bin/env bash
set -euo pipefail

container="${OPERATOR_LEDGER_CONTAINER:-operator-template-ledger}"
docker rm -f "${container}" >/dev/null 2>&1 || true

echo "✅ Local MinIO ledger stopped"
