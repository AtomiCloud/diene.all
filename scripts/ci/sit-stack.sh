#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[[ ${mode} != "up" && ${mode} != "down" ]] && echo "❌ usage: $0 <up|down>" >&2 && exit 2
root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
: "${COMPOSE_PROJECT_NAME:?COMPOSE_PROJECT_NAME must uniquely identify this SIT run}"
project="${COMPOSE_PROJECT_NAME}"
[[ ${project} =~ ^[a-z0-9][a-z0-9_-]{0,127}$ ]] || {
  echo "❌ COMPOSE_PROJECT_NAME must be a safe lowercase Compose identifier" >&2
  exit 2
}
: "${MERCURY_SIT_MATERIAL_DIR:?MERCURY_SIT_MATERIAL_DIR must point at generated bounded secret material}"
[[ ${MERCURY_SIT_MATERIAL_DIR} == /* ]] || {
  echo "❌ MERCURY_SIT_MATERIAL_DIR must be absolute" >&2
  exit 2
}

if [[ ${mode} == "up" ]]; then
  echo "🐳 Starting the two-landscape product-owned SIT stack..."
  if ! docker compose --project-name "${project}" --file scripts/local/docker-compose.yaml up --detach --build --wait; then
    docker compose --project-name "${project}" --file scripts/local/docker-compose.yaml down --volumes --remove-orphans || true
    exit 1
  fi
else
  echo "🧹 Stopping two-landscape SIT products, dependencies, and external controls..."
  docker compose --project-name "${project}" --file scripts/local/docker-compose.yaml down --volumes --remove-orphans
fi
echo "✅ SIT stack action ${mode} completed"
