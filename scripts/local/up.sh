#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
dev_config="config/dev.yaml"
project="${COMPOSE_PROJECT_NAME:-$(yq -r '.compose.project' "${dev_config}")}"

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
export POSTGRES_PORT POSTGRES_DATABASE POSTGRES_USERNAME POSTGRES_PASSWORD REDIS_PORT
export STORAGE_PORT STORAGE_CONSOLE_PORT STORAGE_ACCESS_KEY_ID STORAGE_SECRET_ACCESS_KEY
export OTEL_HTTP_PORT CLICKHOUSE_HTTP_PORT VICTORIA_METRICS_PORT GRAFANA_PORT

echo "🐳 Starting local dependencies for project ${project}..."
docker compose --project-name "${project}" --file scripts/local/docker-compose.yaml up --detach --wait postgres redis minio clickhouse otel-collector victoria-metrics alloy grafana
docker compose --project-name "${project}" --file scripts/local/docker-compose.yaml run --rm minio-create
echo "✅ Local dependencies are ready for project ${project}"
