#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
committed="schemas/go-consumer.schema.json"
generated="$(mktemp)"
trap 'rm -f "${generated}"' EXIT

echo "🧬 Checking generated configuration schema..."
[ -s "${committed}" ] || {
  echo "❌ committed schema ${committed} is missing or empty — refusing an empty comparison" >&2
  exit 1
}
go run ./scripts/local/schema-gen.go --out "${generated}"
[ -s "${generated}" ] || {
  echo "❌ schema generator produced no content — refusing an empty comparison" >&2
  exit 1
}
committed_digest="$(sha256sum "${committed}" | awk '{print $1}')"
generated_digest="$(sha256sum "${generated}" | awk '{print $1}')"
echo "committed ${committed_digest}"
echo "generated ${generated_digest}"
cmp --silent "${committed}" "${generated}" || {
  echo "❌ Configuration schema drifted; run ./scripts/local/schema-gen.sh" >&2
  diff -u "${committed}" "${generated}" >&2 || true
  exit 1
}
echo "✅ Configuration schema is current"
