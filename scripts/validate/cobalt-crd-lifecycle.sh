#!/usr/bin/env bash
set -euo pipefail

rendered="${1:?pass a rendered manifest file}"
expected="${2:-scripts/validate/cobalt-expected-crds.txt}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

yq eval-all -o=json '.' "${rendered}" |
  jq -r 'select(.kind == "CustomResourceDefinition") | .metadata.name' |
  sort -u >"${tmp}/actual.txt"

if ! diff -u "${expected}" "${tmp}/actual.txt"; then
  echo "❌ rendered ESO CRD lifecycle set differs from the pinned 2.7.0 set" >&2
  exit 1
fi

echo "✅ rendered ESO CRD lifecycle set matches pinned ESO 2.7.0"
