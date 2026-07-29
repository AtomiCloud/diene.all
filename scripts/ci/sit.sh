#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/ci/setup.sh
run_id="${MERCURY_SIT_RUN_ID:-ci-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
[[ ${run_id} =~ ^[a-z0-9][a-z0-9_.-]{0,63}$ ]] || {
  echo "❌ MERCURY_SIT_RUN_ID must be a safe lowercase 1-64 character identifier" >&2
  exit 2
}
export MERCURY_SIT_RUN_ID="${run_id}"
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-mercury-webhook-sit-${run_id}}"
material_dir="$(mktemp -d "/tmp/mercury-webhook-${run_id}.XXXXXX")"
export MERCURY_SIT_MATERIAL_DIR="${material_dir}"
compose_attempted=false
cleanup() {
  status=$?
  if [[ ${compose_attempted} == true ]]; then
    ./scripts/ci/sit-stack.sh down || true
  fi
  if [[ ${material_dir} == "/tmp/mercury-webhook-${run_id}."* && -d ${material_dir} ]]; then
    rm -rf -- "${material_dir}"
  fi
  exit "${status}"
}
trap cleanup EXIT
available_port() {
  bun -e 'const listener=Bun.listen({hostname:"127.0.0.1",port:0,socket:{data(){}}});console.log(listener.port);listener.stop()'
}
export MERCURY_TLS_PORT="${MERCURY_TLS_PORT:-$(available_port)}"
export MERCURY_SIT_CONTROL_PORT="${MERCURY_SIT_CONTROL_PORT:-$(available_port)}"
export MERCURY_LAPRAS_PORT="${MERCURY_LAPRAS_PORT:-$(available_port)}"
export MERCURY_FARFETCH_PORT="${MERCURY_FARFETCH_PORT:-$(available_port)}"
export MERCURY_SIT_PUBLIC_ORIGIN="https://127.0.0.1:${MERCURY_TLS_PORT}"
./scripts/sit-control/generate-material.sh "${material_dir}"
bun scripts/sit-control/write-config.ts "${material_dir}"
export MERCURY_SIT_BASE_URL="${MERCURY_SIT_BASE_URL:-${MERCURY_SIT_PUBLIC_ORIGIN}}"
export MERCURY_SIT_CONTROL_URL="${MERCURY_SIT_CONTROL_URL:-http://127.0.0.1:${MERCURY_SIT_CONTROL_PORT}}"
export MERCURY_SIT_CONTROL_BEARER="${MERCURY_SIT_CONTROL_BEARER:-$(<"${material_dir}/sit-control-bearer")}"
export NODE_EXTRA_CA_CERTS="${NODE_EXTRA_CA_CERTS:-${material_dir}/ca/ca.pem}"
compose_attempted=true
./scripts/ci/sit-stack.sh up

echo "🪴 Validating the Garden journey..."
GARDEN_DISABLE_ANALYTICS=true garden --root infra/garden validate
echo "🧪 Running Mercury SIT through Garden..."
GARDEN_DISABLE_ANALYTICS=true garden --root infra/garden test webhook-journey --env ci
echo "✅ Garden SIT journey passed"
