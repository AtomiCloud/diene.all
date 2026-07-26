#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
dev_config="config/dev.yaml"

[[ $# -eq 0 ]] && echo "❌ usage: $0 <command> [args...]" >&2 && exit 2
[ ! -f "${dev_config}" ] && echo "❌ Local development config is missing: ${dev_config}" >&2 && exit 1

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

[[ -z ${ATOMI_POSTGRES__MAIN__HOST} || ${ATOMI_POSTGRES__MAIN__HOST} == "null" ]] && echo "❌ config/dev.yaml postgres.host is missing" >&2 && exit 1
[[ -z ${ATOMI_POSTGRES__MAIN__PORT} || ${ATOMI_POSTGRES__MAIN__PORT} == "null" ]] && echo "❌ config/dev.yaml postgres.port is missing" >&2 && exit 1
[[ -z ${ATOMI_POSTGRES__MAIN__DATABASE} || ${ATOMI_POSTGRES__MAIN__DATABASE} == "null" ]] && echo "❌ config/dev.yaml postgres.database is missing" >&2 && exit 1
[[ -z ${ATOMI_POSTGRES__MAIN__USERNAME} || ${ATOMI_POSTGRES__MAIN__USERNAME} == "null" ]] && echo "❌ config/dev.yaml postgres.username is missing" >&2 && exit 1
[[ -z ${ATOMI_POSTGRES__MAIN__PASSWORD} || ${ATOMI_POSTGRES__MAIN__PASSWORD} == "null" ]] && echo "❌ config/dev.yaml postgres.password is missing" >&2 && exit 1
[[ -z ${ATOMI_CACHE__MAIN__HOST} || ${ATOMI_CACHE__MAIN__HOST} == "null" ]] && echo "❌ config/dev.yaml redis.host is missing" >&2 && exit 1
[[ -z ${ATOMI_CACHE__MAIN__PORT} || ${ATOMI_CACHE__MAIN__PORT} == "null" ]] && echo "❌ config/dev.yaml redis.port is missing" >&2 && exit 1
[[ -z ${ATOMI_CACHE__MAIN__DB} || ${ATOMI_CACHE__MAIN__DB} == "null" ]] && echo "❌ config/dev.yaml redis.cacheDb is missing" >&2 && exit 1
[[ -z ${ATOMI_KV__MAIN__DB} || ${ATOMI_KV__MAIN__DB} == "null" ]] && echo "❌ config/dev.yaml redis.kvDb is missing" >&2 && exit 1
[[ -z ${ATOMI_STORAGE__MAIN__ENDPOINT} || ${ATOMI_STORAGE__MAIN__ENDPOINT} == "null" ]] && echo "❌ config/dev.yaml storage.endpoint is missing" >&2 && exit 1
[[ -z ${ATOMI_STORAGE__MAIN__ACCESS_KEY_ID} || ${ATOMI_STORAGE__MAIN__ACCESS_KEY_ID} == "null" ]] && echo "❌ config/dev.yaml storage.accessKeyId is missing" >&2 && exit 1
[[ -z ${ATOMI_STORAGE__MAIN__SECRET_ACCESS_KEY} || ${ATOMI_STORAGE__MAIN__SECRET_ACCESS_KEY} == "null" ]] && echo "❌ config/dev.yaml storage.secretAccessKey is missing" >&2 && exit 1
[[ -z ${ATOMI_OTEL__LOGS__EXPORTER__OTLP__ENDPOINT} || ${ATOMI_OTEL__LOGS__EXPORTER__OTLP__ENDPOINT} == "null" ]] && echo "❌ config/dev.yaml otel.endpoint is missing" >&2 && exit 1
[[ -z ${ATOMI_ENCRYPTION__KEY} || ${ATOMI_ENCRYPTION__KEY} == "null" ]] && echo "❌ config/dev.yaml encryption.key is missing" >&2 && exit 1

export ATOMI_POSTGRES__MAIN__HOST ATOMI_POSTGRES__MAIN__PORT ATOMI_POSTGRES__MAIN__DATABASE
export ATOMI_POSTGRES__MAIN__USERNAME ATOMI_POSTGRES__MAIN__PASSWORD
export ATOMI_CACHE__MAIN__HOST ATOMI_CACHE__MAIN__PORT ATOMI_CACHE__MAIN__DB
export ATOMI_KV__MAIN__HOST ATOMI_KV__MAIN__PORT ATOMI_KV__MAIN__DB
export ATOMI_STORAGE__MAIN__ENDPOINT ATOMI_STORAGE__MAIN__ACCESS_KEY_ID ATOMI_STORAGE__MAIN__SECRET_ACCESS_KEY
export ATOMI_STORAGE__ARCHIVE__ENDPOINT ATOMI_STORAGE__ARCHIVE__ACCESS_KEY_ID ATOMI_STORAGE__ARCHIVE__SECRET_ACCESS_KEY
export ATOMI_OTEL__LOGS__EXPORTER__OTLP__ENDPOINT ATOMI_OTEL__METRICS__EXPORTER__OTLP__ENDPOINT
export ATOMI_OTEL__TRACES__EXPORTER__OTLP__ENDPOINT ATOMI_ENCRYPTION__KEY
export ATOMI_AUTH__LOGTO__APP_ID="${ATOMI_AUTH__LOGTO__APP_ID:-local-go-consumer}"
export ATOMI_AUTH__LOGTO__APP_SECRET="${ATOMI_AUTH__LOGTO__APP_SECRET:-local-secret}"
export ATOMI_AUTH__LOGTO__MANAGEMENT__CLIENT_ID="${ATOMI_AUTH__LOGTO__MANAGEMENT__CLIENT_ID:-local-management}"
export ATOMI_AUTH__LOGTO__MANAGEMENT__CLIENT_SECRET="${ATOMI_AUTH__LOGTO__MANAGEMENT__CLIENT_SECRET:-local-secret}"

"$@"
echo "✅ Command completed with local development configuration from ${dev_config}"
