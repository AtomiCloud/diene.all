#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
dev_config="config/dev.yaml"
project="${COMPOSE_PROJECT_NAME:-$(yq -r '.compose.project' "${dev_config}")}"

echo "🧹 Stopping local dependencies for project ${project}..."
docker compose --project-name "${project}" --file scripts/local/docker-compose.yaml down --volumes --remove-orphans
echo "✅ Local dependencies stopped for project ${project}"
