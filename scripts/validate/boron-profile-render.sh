#!/usr/bin/env bash
set -euo pipefail

# Garden profile filtering (goals/charts/boron.md + step5-work/ENV-SPEC.md):
# Boron renders ONLY for connected lapras, explicitly inspectable ditto, and
# independently selectable registered clusters. eevee, plusle, minun, rotom,
# and absol must FAIL to render.

chart="infra/root_chart"

echo "🔎 asserting Boron renders for allowed profiles"

# Included: connected lapras (default overlay) and explicitly inspectable ditto.
helm template t "${chart}" -f "${chart}/values.lapras.yaml" >/dev/null
helm template t "${chart}" -f "${chart}/values.ditto.yaml" >/dev/null
# Registered-cluster admin use stays independently selectable.
helm template t "${chart}" --set installation.profile=registered >/dev/null

echo "🧪 asserting excluded profiles fail to render"

for profile in eevee plusle minun rotom absol; do
  if helm template t "${chart}" --set "installation.profile=${profile}" >/dev/null 2>&1; then
    echo "❌ profile render: boron rendered for excluded profile ${profile}" >&2
    exit 1
  fi
done

# ditto without the explicit inspect opt-in must also refuse.
if helm template t "${chart}" --set installation.profile=ditto --set installation.dittoInspect=false >/dev/null 2>&1; then
  echo "❌ profile render: ditto rendered without the explicit inspect opt-in" >&2
  exit 1
fi

echo "✅ boron profile-render assertions passed (lapras/ditto/registered in; eevee/plusle/minun/rotom/absol out)"
