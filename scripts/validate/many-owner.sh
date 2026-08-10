#!/usr/bin/env bash
set -euo pipefail

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT

printf '%s\n' .gitignore Taskfile.yaml CLAUDE.md >"${tmp}"
find nix -maxdepth 1 -type f -name '*.nix' | sort >>"${tmp}"
find .github/workflows -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) | sort >>"${tmp}"

while IFS= read -r file; do
  [ -f "${file}" ] || {
    echo "❌ many-owner target '${file}' is missing" >&2
    exit 1
  }
  markers="$(rg '### [A-Za-z0-9._:-]+' "${file}" | rg -v '#### source:' | sed -E 's/.*### ([A-Za-z0-9._:-]+).*/\1/' || true)"
  [ -z "${markers}" ] && echo "❌ many-owner target '${file}' has no keyed block" >&2 && exit 1
  duplicate="$(echo "${markers}" | sort | uniq -d | head -n 1)"
  [ -n "${duplicate}" ] && echo "❌ many-owner target '${file}' repeats owner key '${duplicate}'" >&2 && exit 1
  marker_count="$(echo "${markers}" | sed '/^$/d' | wc -l | tr -d ' ')"
  source_count="$(rg -c '#### source: [A-Za-z0-9._:/-]+' "${file}" || true)"
  [ "${marker_count}" -ne "${source_count}" ] && echo "❌ '${file}' needs one provenance line per keyed block" >&2 && exit 1
done <"${tmp}"

echo "✅ Many-owner files use unique keyed blocks"
