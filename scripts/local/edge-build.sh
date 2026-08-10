#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

entry="src/lib/retrievers/server.ts"
[[ ! -f ${entry} ]] && echo "❌ edge retriever entry is missing: ${entry}" >&2 && exit 1

edge_tmp_dir="$(mktemp -d)"
trap 'rm -rf "${edge_tmp_dir}"' EXIT

echo "🌐 Building the server retriever for a browser/Workers runtime..."
bun build "${entry}" \
  --outfile "${edge_tmp_dir}/server.js" \
  --metafile="${edge_tmp_dir}/metafile.json" \
  --format esm \
  --target browser

reachable_runtime_imports="$(jq -r '
  [
    .outputs
    | to_entries[]
    | .value.imports[]?
    | select(.path | test("^(node|bun):"))
    | .path
  ]
  | unique
  | .[]
' "${edge_tmp_dir}/metafile.json")"

# Check emitted imports because Bun's input graph also lists dependencies removed by tree-shaking.
[[ -n ${reachable_runtime_imports} ]] && echo "❌ edge build has reachable node:* or bun:* runtime imports:" >&2 && printf '%s\n' "${reachable_runtime_imports}" >&2 && exit 1

echo "✅ Server retriever and reachable runtime graph bundle for browser with no node:* or bun:* imports"
