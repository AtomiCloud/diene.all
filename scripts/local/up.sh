#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
dev_config="config/dev.yaml"
[ ! -f "${dev_config}" ] && echo "❌ Local development config is missing: ${dev_config}" >&2 && exit 1
project="${COMPOSE_PROJECT_NAME:-$(yq -r '.compose.project' "${dev_config}")}"
[[ -z ${project} || ${project} == "null" ]] && echo "❌ config/dev.yaml compose.project is missing" >&2 && exit 1
[[ ${project} != diene-go-consumer* ]] && echo "❌ Compose project must start with diene-go-consumer, got '${project}'" >&2 && exit 1

POSTGRES_PORT="$(yq -r '.postgres.port' "${dev_config}")"
POSTGRES_DATABASE="$(yq -r '.postgres.database' "${dev_config}")"
POSTGRES_USERNAME="$(yq -r '.postgres.username' "${dev_config}")"
POSTGRES_PASSWORD="$(yq -r '.postgres.password' "${dev_config}")"
REDIS_PORT="$(yq -r '.redis.port' "${dev_config}")"
STORAGE_PORT="$(yq -r '.storage.endpoint | sub("^.*:"; "")' "${dev_config}")"
STORAGE_CONSOLE_PORT="$(yq -r '.storage.consolePort' "${dev_config}")"
STORAGE_ACCESS_KEY_ID="$(yq -r '.storage.accessKeyId' "${dev_config}")"
STORAGE_SECRET_ACCESS_KEY="$(yq -r '.storage.secretAccessKey' "${dev_config}")"
OTEL_HTTP_PORT="$(yq -r '.otel.endpoint | sub("^.*:"; "")' "${dev_config}")"
CLICKHOUSE_HTTP_PORT="$(yq -r '.clickhouse.endpoint | sub("^.*:"; "")' "${dev_config}")"
VICTORIA_METRICS_PORT="$(yq -r '.victoriaMetrics.endpoint | sub("^.*:"; "")' "${dev_config}")"
GRAFANA_PORT="$(yq -r '.grafana.port' "${dev_config}")"
[[ -z ${POSTGRES_PORT} || ${POSTGRES_PORT} == "null" ]] && echo "❌ config/dev.yaml postgres.port is missing" >&2 && exit 1
[[ -z ${POSTGRES_DATABASE} || ${POSTGRES_DATABASE} == "null" ]] && echo "❌ config/dev.yaml postgres.database is missing" >&2 && exit 1
[[ -z ${POSTGRES_USERNAME} || ${POSTGRES_USERNAME} == "null" ]] && echo "❌ config/dev.yaml postgres.username is missing" >&2 && exit 1
[[ -z ${POSTGRES_PASSWORD} || ${POSTGRES_PASSWORD} == "null" ]] && echo "❌ config/dev.yaml postgres.password is missing" >&2 && exit 1
[[ -z ${REDIS_PORT} || ${REDIS_PORT} == "null" ]] && echo "❌ config/dev.yaml redis.port is missing" >&2 && exit 1
[[ -z ${STORAGE_PORT} || ${STORAGE_PORT} == "null" ]] && echo "❌ config/dev.yaml storage.endpoint port is missing" >&2 && exit 1
[[ -z ${STORAGE_CONSOLE_PORT} || ${STORAGE_CONSOLE_PORT} == "null" ]] && echo "❌ config/dev.yaml storage.consolePort is missing" >&2 && exit 1
[[ -z ${STORAGE_ACCESS_KEY_ID} || ${STORAGE_ACCESS_KEY_ID} == "null" ]] && echo "❌ config/dev.yaml storage.accessKeyId is missing" >&2 && exit 1
[[ -z ${STORAGE_SECRET_ACCESS_KEY} || ${STORAGE_SECRET_ACCESS_KEY} == "null" ]] && echo "❌ config/dev.yaml storage.secretAccessKey is missing" >&2 && exit 1
[[ -z ${OTEL_HTTP_PORT} || ${OTEL_HTTP_PORT} == "null" ]] && echo "❌ config/dev.yaml otel.endpoint port is missing" >&2 && exit 1
[[ -z ${CLICKHOUSE_HTTP_PORT} || ${CLICKHOUSE_HTTP_PORT} == "null" ]] && echo "❌ config/dev.yaml clickhouse.endpoint port is missing" >&2 && exit 1
[[ -z ${VICTORIA_METRICS_PORT} || ${VICTORIA_METRICS_PORT} == "null" ]] && echo "❌ config/dev.yaml victoriaMetrics.endpoint port is missing" >&2 && exit 1
[[ -z ${GRAFANA_PORT} || ${GRAFANA_PORT} == "null" ]] && echo "❌ config/dev.yaml grafana.port is missing" >&2 && exit 1
export POSTGRES_PORT POSTGRES_DATABASE POSTGRES_USERNAME POSTGRES_PASSWORD REDIS_PORT
export STORAGE_PORT STORAGE_CONSOLE_PORT STORAGE_ACCESS_KEY_ID STORAGE_SECRET_ACCESS_KEY
export OTEL_HTTP_PORT CLICKHOUSE_HTTP_PORT VICTORIA_METRICS_PORT GRAFANA_PORT

echo "🐳 Starting local dependencies for project ${project}..."
docker compose --project-name "${project}" --file scripts/local/docker-compose.yaml up --detach --wait postgres redis minio clickhouse otel-collector victoria-metrics alloy grafana
docker compose --project-name "${project}" --file scripts/local/docker-compose.yaml run --rm minio-create
# READINESS GATE ON THE OTLP RECEIVER PORT ITSELF — not by circumstance, not by proxy.
# `docker compose --wait` blocks until HEALTHY only for services that DECLARE a
# healthcheck; alloy has none, so --wait returns as soon as its container is STARTED,
# before its OTLP receiver on :${OTEL_HTTP_PORT} is listening. The worker emits OTLP
# there and fast-fails with a connection refusal (~0.09s) if it is not yet up. We gate
# on the ACTUAL port the worker uses — NOT alloy's /-/ready admin server on 12345, which
# proves process liveness rather than receiver acceptance.
echo "⏳ Waiting for the OTLP receiver on 127.0.0.1:${OTEL_HTTP_PORT}..."
otlp_ready=""
otlp_waited=0
for _ in $(seq 1 60); do
  if timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/${OTEL_HTTP_PORT}" 2>/dev/null ||
    nc -z 127.0.0.1 "${OTEL_HTTP_PORT}" 2>/dev/null; then
    otlp_ready=1
    break
  fi
  otlp_waited=$((otlp_waited + 1))
  sleep 1
done
[ -n "${otlp_ready}" ] || {
  echo "❌ OTLP receiver on :${OTEL_HTTP_PORT} did not accept a connection within 60s" >&2
  exit 1
}
# Timing is the PROOF the gate engaged: otlp_gate_waited_s=0 means alloy was already
# accepting when --wait returned (the race did not occur this run — inconclusive for the
# fix); >0 means the gate blocked while alloy's receiver came up (the fix demonstrably acted).
echo "🔌 OTLP receiver accepted after otlp_gate_waited_s=${otlp_waited} (0 = alloy already warm)"
echo "✅ Local dependencies are ready for project ${project}"
