#!/usr/bin/env bash
set -euo pipefail

mode="${1:-journey}"
[[ ${mode} != "journey" && ${mode} != "coverage" ]] && echo "❌ usage: $0 <journey|coverage>" >&2 && exit 2
root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
run_id="${MERCURY_SIT_RUN_ID:-${2:-}}"
if [[ -n ${run_id} ]]; then
  [[ ${run_id} =~ ^[a-z0-9][a-z0-9_.-]{0,63}$ ]] || {
    echo "❌ local SIT run ID is invalid" >&2
    exit 2
  }
  state_file="/tmp/mercury-webhook-${UID}/${run_id}.env"
  [[ -f ${state_file} ]] || {
    echo "❌ no local SIT state exists for ${run_id}" >&2
    exit 2
  }
  while IFS='=' read -r name value; do
    case "${name}" in
    MERCURY_SIT_MATERIAL_DIR | MERCURY_TLS_PORT | MERCURY_SIT_CONTROL_PORT)
      printf -v "${name}" '%s' "${value}"
      export "${name?}"
      ;;
    esac
  done <"${state_file}"
fi
: "${MERCURY_TLS_PORT:?MERCURY_TLS_PORT or a local run ID is required}"
: "${MERCURY_SIT_CONTROL_PORT:?MERCURY_SIT_CONTROL_PORT or a local run ID is required}"
export MERCURY_SIT_BASE_URL="${MERCURY_SIT_BASE_URL:-https://127.0.0.1:${MERCURY_TLS_PORT}}"
export MERCURY_SIT_CONTROL_URL="${MERCURY_SIT_CONTROL_URL:-http://127.0.0.1:${MERCURY_SIT_CONTROL_PORT}}"
if [[ -n ${MERCURY_SIT_MATERIAL_DIR:-} ]]; then
  export MERCURY_SIT_CONTROL_BEARER="${MERCURY_SIT_CONTROL_BEARER:-$(<"${MERCURY_SIT_MATERIAL_DIR}/sit-control-bearer")}"
  export NODE_EXTRA_CA_CERTS="${NODE_EXTRA_CA_CERTS:-${MERCURY_SIT_MATERIAL_DIR}/ca/ca.pem}"
fi
: "${MERCURY_SIT_CONTROL_BEARER:?MERCURY_SIT_CONTROL_BEARER is required}"
: "${NODE_EXTRA_CA_CERTS:?NODE_EXTRA_CA_CERTS must point to the bounded SIT CA}"

if [[ ${mode} == "coverage" ]]; then
  echo "🧪 Running Mercury SIT with coverage..."
  bun test --config=bunfig.sit.toml --coverage
else
  echo "🧪 Running the bounded Mercury provider-to-sink journey..."
  bun test --config=bunfig.sit.toml
fi
echo "✅ Mercury SIT journey passed"
