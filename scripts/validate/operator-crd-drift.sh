#!/usr/bin/env bash
set -euo pipefail

# Regeneration overwrites the working tree, so any remaining diff is real committed drift.

crd_dir="infra/root_chart/templates/crds"

echo "🔨 regenerating CRDs and deepcopy from ./api"

controller-gen crd paths=./api/... output:crd:dir="${crd_dir}"
controller-gen object paths=./api/...

# The generated deepcopy is emitted once per API package. Discover every
# zz_generated.deepcopy.go under api/ dynamically so a new api/<group>/<version>
# tree (fleet today, problems next) is part of the drift decision the moment it
# lands, rather than being silently omitted the way a hardcoded single path was.
deepcopy_paths=()
while IFS= read -r generated; do
  deepcopy_paths+=("${generated}")
done < <(find api -type f -name 'zz_generated.deepcopy.go' | sort)

# A gate that checks nothing must fail, not pass: an empty CRD dir or a missing
# deepcopy means discovery broke, and a silent green would be worse than a red.
[ ! -d "${crd_dir}" ] && echo "❌ operator CRD drift: missing CRD directory ${crd_dir}" >&2 && exit 1
[ "${#deepcopy_paths[@]}" -eq 0 ] && echo "❌ operator CRD drift: found no generated deepcopy under api/ — the drift decision would be vacuous" >&2 && exit 1

targets=("${crd_dir}" "${deepcopy_paths[@]}")

echo "🔎 drift targets ($((${#targets[@]}))):"
for target in "${targets[@]}"; do
  echo "  - ${target}"
done

# The diff compares the regenerated working tree against the index, so a commit
# whose staged generated artifacts already match regeneration passes cleanly
# while a stale or hand-edited artifact reddens. ls-files --others additionally
# catches a brand-new UNTRACKED generated file — the deepcopy a fresh API package
# emits — which a diff-only check would silently ignore.
drift="$(git --no-pager diff -- "${targets[@]}")"
untracked="$(git ls-files --others --exclude-standard -- "${targets[@]}")"
if [ -n "${drift}" ] || [ -n "${untracked}" ]; then
  [ -n "${drift}" ] && echo "${drift}" >&2
  [ -n "${untracked}" ] && echo "untracked generated files (regenerate and commit them):" >&2 && echo "${untracked}" >&2
  echo "❌ operator CRD drift: generated CRDs/deepcopy differ from committed — run scripts/local/operator-manifests.sh" >&2
  exit 1
fi

echo "✅ operator CRD drift check passed"
