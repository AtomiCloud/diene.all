#!/usr/bin/env bash
set -euo pipefail

# Regenerate the typed OA3 client from the reviewed spec. The generation
# CONTRACT is: openapi/service.openapi.yaml + swagger_parser.yaml → retrofit
# client under lib/src/generated → build_runner parts. api-engine's OA3Adapter
# wraps the result into Result/Problem.
spec="${1:-openapi/service.openapi.yaml}"
[ -f "${spec}" ] || {
  echo "❌ OpenAPI spec '${spec}' does not exist" >&2
  exit 1
}

echo "🧬 Generating the typed OA3 client..."
flutter pub run swagger_parser
flutter pub run build_runner build
dart format lib/src/generated >/dev/null

echo "✅ Typed OA3 client generated"
