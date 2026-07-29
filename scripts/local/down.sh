#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
run_id="${MERCURY_SIT_RUN_ID:-${1:-}}"
: "${run_id:?set MERCURY_SIT_RUN_ID or pass the run ID to down.sh}"
[[ ${run_id} =~ ^[a-z0-9][a-z0-9_.-]{0,63}$ ]] || exit 2
state_root="/tmp/mercury-webhook-${UID}"
state_file="${state_root}/${run_id}.env"
[[ -f ${state_file} ]] || {
  echo "❌ no local SIT state exists for ${run_id}" >&2
  exit 2
}
while IFS='=' read -r name value; do
  case "${name}" in
  COMPOSE_PROJECT_NAME | MERCURY_SIT_MATERIAL_DIR | MERCURY_TLS_PORT | MERCURY_SIT_CONTROL_PORT | MERCURY_LAPRAS_PORT | MERCURY_FARFETCH_PORT)
    printf -v "${name}" '%s' "${value}"
    export "${name?}"
    ;;
  esac
done <"${state_file}"
project="${COMPOSE_PROJECT_NAME}"
material_dir="${MERCURY_SIT_MATERIAL_DIR}"
export MERCURY_SIT_PUBLIC_ORIGIN="https://127.0.0.1:${MERCURY_TLS_PORT}"

echo "🧹 Stopping Mercury local stack ${run_id}..."
docker compose --project-name "${project}" --file scripts/local/docker-compose.yaml down --volumes --remove-orphans
if [[ ${material_dir} == "${state_root}/${run_id}.material."* && -d ${material_dir} ]]; then
  rm -rf -- "${material_dir}"
fi
rm -f -- "${state_file}"
echo "✅ Mercury local stack stopped"
