#!/usr/bin/env bash
set -euo pipefail

container="${OPERATOR_LEDGER_CONTAINER:-operator-template-ledger}"
image="${MINIO_IMAGE:-minio/minio:RELEASE.2024-01-16T16-07-38Z}"
port="${LEDGER_PORT:-19000}"
access_key="${LEDGER_ACCESS_KEY:-minioadmin}"
secret_key="${LEDGER_SECRET_KEY:-minioadmin}"
running="$(docker inspect --format '{{.State.Running}}' "${container}" 2>/dev/null || true)"
binding="$(docker port "${container}" 9000/tcp 2>/dev/null || true)"
if [ "${running}" = "true" ] && printf '%s\n' "${binding}" | tr -d '\r' | grep -Fqx -- "127.0.0.1:${port}"; then
  echo "✅ Local MinIO ledger already running on 127.0.0.1:${port}"
  exit 0
fi

docker rm -f "${container}" >/dev/null 2>&1 || true
docker run -d --name "${container}" -p "127.0.0.1:${port}:9000" -e "MINIO_ROOT_USER=${access_key}" -e "MINIO_ROOT_PASSWORD=${secret_key}" "${image}" server /data >/dev/null

echo "✅ Local MinIO ledger started on 127.0.0.1:${port}"
