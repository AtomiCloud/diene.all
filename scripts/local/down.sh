#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
dev_config="config/dev.yaml"
project="${COMPOSE_PROJECT_NAME:-}"
[ -z "${project}" ] && [ -f "${dev_config}" ] && project="$(yq -r '.compose.project' "${dev_config}" 2>/dev/null || true)"
if [[ -z ${project} || ${project} == "null" ]]; then
  echo "⚠️ Local stack teardown skipped because no compose project could be resolved from ${dev_config}" >&2
  echo "✅ Local dependency teardown finished with no resolved project"
  exit 0
fi
if [[ ${project} != diene-go-consumer* ]]; then
  echo "⚠️ Local stack teardown skipped for unsafe compose project '${project}'" >&2
  echo "✅ Local dependency teardown finished without touching project ${project}"
  exit 0
fi

echo "🧹 Stopping local dependencies for project ${project}..."
docker compose --project-name "${project}" --file scripts/local/docker-compose.yaml down --volumes --remove-orphans || echo "⚠️ Local stack was already absent or teardown was unavailable for project ${project}" >&2
echo "✅ Local dependency teardown finished for project ${project}"
