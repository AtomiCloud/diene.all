#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
run_id="${MERCURY_SIT_RUN_ID:-${1:-}}"
if [[ -z ${run_id} ]]; then
  run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM}"
fi
[[ ${run_id} =~ ^[a-z0-9][a-z0-9_.-]{0,63}$ ]] || {
  echo "❌ MERCURY_SIT_RUN_ID must be a safe lowercase 1-64 character identifier" >&2
  exit 2
}
export MERCURY_SIT_RUN_ID="${run_id}"
project="${COMPOSE_PROJECT_NAME:-mercury-webhook-${run_id}}"
[[ ${project} =~ ^[a-z0-9][a-z0-9_-]{0,127}$ ]] || {
  echo "❌ COMPOSE_PROJECT_NAME must be a safe lowercase Compose identifier" >&2
  exit 2
}
export COMPOSE_PROJECT_NAME="${project}"
state_root="/tmp/mercury-webhook-${UID}"
mkdir -p "${state_root}"
state_file="${state_root}/${run_id}.env"
material_owned=false
if [[ -z ${MERCURY_SIT_MATERIAL_DIR:-} ]]; then
  material_dir="$(mktemp -d "${state_root}/${run_id}.material.XXXXXX")"
  material_owned=true
else
  material_dir="${MERCURY_SIT_MATERIAL_DIR}"
fi
[[ ${material_dir} == /* && ${material_dir} != *$'\n'* ]] || {
  echo "❌ MERCURY_SIT_MATERIAL_DIR must be an absolute single-line path" >&2
  exit 2
}
export MERCURY_SIT_MATERIAL_DIR="${material_dir}"
compose_attempted=false
cleanup_failed_start() {
  status=$?
  if [[ ${status} -ne 0 ]]; then
    if [[ ${compose_attempted} == true ]]; then
      docker compose --project-name "${project}" --file scripts/local/docker-compose.yaml down --volumes --remove-orphans || true
    fi
    if [[ ${material_owned} == true && ${material_dir} == "${state_root}/"* && -d ${material_dir} ]]; then
      rm -rf -- "${material_dir}"
    fi
    rm -f -- "${state_file}"
  fi
  exit "${status}"
}
trap cleanup_failed_start EXIT

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
bun -e 'await Bun.write(process.argv[1], process.argv.slice(2).join("\n")+"\n")' \
  "${state_file}" \
  "MERCURY_SIT_RUN_ID=${run_id}" \
  "COMPOSE_PROJECT_NAME=${project}" \
  "MERCURY_SIT_MATERIAL_DIR=${material_dir}" \
  "MERCURY_TLS_PORT=${MERCURY_TLS_PORT}" \
  "MERCURY_SIT_CONTROL_PORT=${MERCURY_SIT_CONTROL_PORT}" \
  "MERCURY_LAPRAS_PORT=${MERCURY_LAPRAS_PORT}" \
  "MERCURY_FARFETCH_PORT=${MERCURY_FARFETCH_PORT}"

echo "🐳 Starting both Mercury landscapes, bounded dependencies, TLS gateway, and external SIT control..."
compose_attempted=true
docker compose --project-name "${project}" --file scripts/local/docker-compose.yaml up --detach --build --wait
compose_attempted=false
trap - EXIT
echo "✅ Mercury local stack ${run_id} is ready at https://127.0.0.1:${MERCURY_TLS_PORT}"
echo "   CA: ${material_dir}/ca/ca.pem"
echo "   Control: http://127.0.0.1:${MERCURY_SIT_CONTROL_PORT}"
echo "   Stop: MERCURY_SIT_RUN_ID=${run_id} ./scripts/local/down.sh"
