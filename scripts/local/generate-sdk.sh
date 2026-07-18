#!/usr/bin/env bash
set -euo pipefail

spec="${1:-openapi/service.openapi.yaml}"
[ ! -f "${spec}" ] && echo "❌ OpenAPI specification '${spec}' does not exist" >&2 && exit 1

echo "🧬 Generating the typed OA3 client..."
flutter pub run swagger_parser --schema_path "${spec}"
flutter pub run build_runner build
dart format lib/generated/service

echo "✅ Typed OA3 client generated"
