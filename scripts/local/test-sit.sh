#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
journey="${2:-}"
[[ $# -gt 2 || (${mode} != "binary" && ${mode} != "parity") ]] && {
  echo "❌ usage: $0 <binary|parity> [journey-regex]" >&2
  exit 2
}

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

export SIT_DRIVER="${mode}"
export CLI_BIN="${CLI_BIN:-dist/go-consumer}"
export GO_CONSUMER_ROOT="${root_dir}"

[[ ${CLI_BIN} == /* ]] && artifact="${CLI_BIN}" || artifact="${root_dir}/${CLI_BIN}"
[ ! -x "${artifact}" ] && echo "❌ SIT binary missing or not executable: ${artifact}" >&2 && exit 1

dev_config="config/dev.yaml"
export E2E_PREVIEW_LANDSCAPE="${E2E_PREVIEW_LANDSCAPE:-lapras}"
export E2E_PREVIEW_PLATFORM="${E2E_PREVIEW_PLATFORM:-diene}"
export E2E_PREVIEW_SERVICE="${E2E_PREVIEW_SERVICE:-go-consumer}"
export E2E_PREVIEW_MODULE="${E2E_PREVIEW_MODULE:-worker}"
export E2E_PREVIEW_VERSION="${E2E_PREVIEW_VERSION:-0.0.0}"
export E2E_PREVIEW_BASE_URL="${E2E_PREVIEW_BASE_URL:-http://localhost:8080}"
export E2E_PREVIEW_OTLP_ENDPOINT="${E2E_PREVIEW_OTLP_ENDPOINT:-$(yq -r '.otel.endpoint' "${dev_config}")}"
export E2E_PREVIEW_ISSUER="${E2E_PREVIEW_ISSUER:-http://localhost:3001/oidc}"
export E2E_PREVIEW_AUDIENCE="${E2E_PREVIEW_AUDIENCE:-go-consumer}"
export E2E_PREVIEW_JWKS_URI="${E2E_PREVIEW_JWKS_URI:-http://localhost:3001/oidc/jwks}"
export E2E_PREVIEW_RESOURCE="${E2E_PREVIEW_RESOURCE:-control-plane}"

export ATOMI_OTEL__LOGS__EXPORTER__OTLP__ENABLED="${ATOMI_OTEL__LOGS__EXPORTER__OTLP__ENABLED:-true}"
export ATOMI_OTEL__METRICS__EXPORTER__OTLP__ENABLED="${ATOMI_OTEL__METRICS__EXPORTER__OTLP__ENABLED:-true}"
export ATOMI_OTEL__TRACES__EXPORTER__OTLP__ENABLED="${ATOMI_OTEL__TRACES__EXPORTER__OTLP__ENABLED:-true}"
export SIT_CLICKHOUSE_ENDPOINT="${SIT_CLICKHOUSE_ENDPOINT:-$(yq -r '.clickhouse.endpoint' "${dev_config}")}"
export SIT_VICTORIA_METRICS_ENDPOINT="${SIT_VICTORIA_METRICS_ENDPOINT:-$(yq -r '.victoriaMetrics.endpoint' "${dev_config}")}"
export SIT_STORAGE_BUCKET="${SIT_STORAGE_BUCKET:-$(yq -r '.storage.MAIN.bucket' config/settings.yaml)}"
export SIT_STORAGE_REGION="${SIT_STORAGE_REGION:-$(yq -r '.storage.MAIN.region' config/settings.yaml)}"

test_args=(-v -timeout 4m)
if [[ -n ${journey} ]]; then
  test_args+=(-run "${journey}")
fi
test_args+=(./tests/sit/...)

echo "🧪 Running Go SIT journeys with ${mode} driver${journey:+ matching ${journey}}..."
./scripts/local/with-dev-env.sh go test "${test_args[@]}"
echo "✅ Go SIT journeys passed with ${mode} driver"
