#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
dev_config="config/dev.yaml"
[[ $# -eq 0 ]] && echo "❌ usage: $0 <command> [args...]" >&2 && exit 2

BUN_CONSUMER_ROOT="${root_dir}"
ATOMI_POSTGRES__MAIN__HOST="$(yq -r '.postgres.host' "${dev_config}")"
ATOMI_POSTGRES__MAIN__PORT="$(yq -r '.postgres.port' "${dev_config}")"
ATOMI_POSTGRES__MAIN__DATABASE="$(yq -r '.postgres.database' "${dev_config}")"
ATOMI_POSTGRES__MAIN__USERNAME="$(yq -r '.postgres.username' "${dev_config}")"
ATOMI_POSTGRES__MAIN__PASSWORD="$(yq -r '.postgres.password' "${dev_config}")"
ATOMI_CACHE__MAIN__HOST="$(yq -r '.redis.host' "${dev_config}")"
ATOMI_CACHE__MAIN__PORT="$(yq -r '.redis.port' "${dev_config}")"
ATOMI_CACHE__MAIN__DB="$(yq -r '.redis.cacheDb' "${dev_config}")"
ATOMI_KV__MAIN__HOST="$(yq -r '.redis.host' "${dev_config}")"
ATOMI_KV__MAIN__PORT="$(yq -r '.redis.port' "${dev_config}")"
ATOMI_KV__MAIN__DB="$(yq -r '.redis.kvDb' "${dev_config}")"
ATOMI_STORAGE__MAIN__ENDPOINT="$(yq -r '.storage.endpoint' "${dev_config}")"
ATOMI_STORAGE__MAIN__ACCESS_KEY_ID="$(yq -r '.storage.accessKeyId' "${dev_config}")"
ATOMI_STORAGE__MAIN__SECRET_ACCESS_KEY="$(yq -r '.storage.secretAccessKey' "${dev_config}")"
ATOMI_STORAGE__ARCHIVE__ENDPOINT="$(yq -r '.storage.endpoint' "${dev_config}")"
ATOMI_STORAGE__ARCHIVE__ACCESS_KEY_ID="$(yq -r '.storage.accessKeyId' "${dev_config}")"
ATOMI_STORAGE__ARCHIVE__SECRET_ACCESS_KEY="$(yq -r '.storage.secretAccessKey' "${dev_config}")"
ATOMI_OTEL__LOGS__EXPORTER__OTLP__ENDPOINT="$(yq -r '.otel.endpoint' "${dev_config}")"
ATOMI_OTEL__METRICS__EXPORTER__OTLP__ENDPOINT="$(yq -r '.otel.endpoint' "${dev_config}")"
ATOMI_OTEL__TRACES__EXPORTER__OTLP__ENDPOINT="$(yq -r '.otel.endpoint' "${dev_config}")"
ATOMI_ENCRYPTION__KEY="$(yq -r '.encryption.key' "${dev_config}")"
export BUN_CONSUMER_ROOT
export ATOMI_POSTGRES__MAIN__HOST ATOMI_POSTGRES__MAIN__PORT ATOMI_POSTGRES__MAIN__DATABASE
export ATOMI_POSTGRES__MAIN__USERNAME ATOMI_POSTGRES__MAIN__PASSWORD
export ATOMI_CACHE__MAIN__HOST ATOMI_CACHE__MAIN__PORT ATOMI_CACHE__MAIN__DB
export ATOMI_KV__MAIN__HOST ATOMI_KV__MAIN__PORT ATOMI_KV__MAIN__DB
export ATOMI_STORAGE__MAIN__ENDPOINT ATOMI_STORAGE__MAIN__ACCESS_KEY_ID ATOMI_STORAGE__MAIN__SECRET_ACCESS_KEY
export ATOMI_STORAGE__ARCHIVE__ENDPOINT ATOMI_STORAGE__ARCHIVE__ACCESS_KEY_ID ATOMI_STORAGE__ARCHIVE__SECRET_ACCESS_KEY
export ATOMI_OTEL__LOGS__EXPORTER__OTLP__ENDPOINT ATOMI_OTEL__METRICS__EXPORTER__OTLP__ENDPOINT
export ATOMI_OTEL__TRACES__EXPORTER__OTLP__ENDPOINT ATOMI_ENCRYPTION__KEY
export ATOMI_AUTH__LOGTO__APP_ID="${ATOMI_AUTH__LOGTO__APP_ID:-local-consumer}"
export ATOMI_AUTH__LOGTO__APP_SECRET="${ATOMI_AUTH__LOGTO__APP_SECRET:-local-secret}"
export ATOMI_AUTH__LOGTO__MANAGEMENT__CLIENT_ID="${ATOMI_AUTH__LOGTO__MANAGEMENT__CLIENT_ID:-local-management}"
export ATOMI_AUTH__LOGTO__MANAGEMENT__CLIENT_SECRET="${ATOMI_AUTH__LOGTO__MANAGEMENT__CLIENT_SECRET:-local-secret}"

"$@"
echo "✅ Command completed with local development configuration"
