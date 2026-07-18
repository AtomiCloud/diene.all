#!/usr/bin/env bash
set -euo pipefail

matrix="$(EVENT=push bash ./scripts/ci/cd-matrix.sh)"
jq -e '.include | length == 4' <<<"${matrix}" >/dev/null || {
  echo "❌ tag CD matrix must contain four landscapes" >&2
  exit 1
}
jq -e '[.include[].flavor] == ["lapras", "pichu", "pikachu", "raichu"]' <<<"${matrix}" >/dev/null || {
  echo "❌ tag CD matrix flavor ordering is invalid" >&2
  exit 1
}
manual="$(EVENT=workflow_dispatch SEL=pichu bash ./scripts/ci/cd-matrix.sh)"
jq -e '.include == [{flavor: "pichu", apple_id: "", package_name: "cloud.atomi.pichu.platform.service.app"}]' <<<"${manual}" >/dev/null || {
  echo "❌ manual CD matrix filtering is invalid" >&2
  exit 1
}

echo "✅ CD matrix has four tokenized landscapes and manual filtering"
