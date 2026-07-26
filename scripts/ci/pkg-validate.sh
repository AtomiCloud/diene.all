#!/usr/bin/env bash
set -euo pipefail

mode="${1:-all}"
[ "${mode}" != "module-path" ] && [ "${mode}" != "vet" ] && [ "${mode}" != "api-compat" ] && [ "${mode}" != "export-docs" ] && [ "${mode}" != "examples" ] && [ "${mode}" != "all" ] && echo "❌ unknown package-validation mode '${mode}'" >&2 && exit 1

./scripts/ci/setup.sh

if [ "${mode}" = "module-path" ] || [ "${mode}" = "all" ]; then
  ./scripts/validate/go-module-path.sh
  ./scripts/validate/go-lib-workflows.sh all
fi
if [ "${mode}" = "vet" ] || [ "${mode}" = "all" ]; then
  ./scripts/validate/go-vet.sh
fi
if [ "${mode}" = "api-compat" ] || [ "${mode}" = "all" ]; then
  ./scripts/validate/go-api-compat.sh
fi
if [ "${mode}" = "export-docs" ] || [ "${mode}" = "all" ]; then
  ./scripts/validate/go-export-docs.sh
  ./scripts/validate/config-skill-docs.sh
fi
if [ "${mode}" = "examples" ] || [ "${mode}" = "all" ]; then
  ./scripts/validate/go-examples.sh
fi

echo "✅ Go library ${mode} validation passed"
