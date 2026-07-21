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
dart run swagger_parser
dart run build_runner build --delete-conflicting-outputs
dart format lib/src/generated >/dev/null

echo "✅ Typed OA3 client generated"
