#!/usr/bin/env bash
set -euo pipefail

vendor_dir=".claude/skills/vendor"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

bash scripts/local/skills-sync.sh

tracked="${work_dir}/tracked.txt"
if ! git ls-files -- "${vendor_dir}" >"${tracked}"; then
  echo "❌ Failed to list tracked vendored skills (git ls-files)" >&2
  exit 1
fi

# .gitkeep only keeps the directory alive; it can never witness stale content.
subjects="${work_dir}/subjects.txt"
subjects_status=0
grep -F -x -v "${vendor_dir}/.gitkeep" "${tracked}" >"${subjects}" || subjects_status=$?
if [ "${subjects_status}" -ge 2 ]; then
  echo "❌ Failed to filter tracked vendored skills (grep exit ${subjects_status})" >&2
  exit "${subjects_status}"
fi
subject_count="$(wc -l <"${subjects}")"

echo "ℹ️ Tracked vendored-skill subjects: ${subject_count}"
if [ "${subject_count}" -eq 0 ]; then
  echo "❌ No tracked subject under ${vendor_dir}; the freshness gate would pass vacuously" >&2
  exit 1
fi

porcelain="${work_dir}/porcelain.txt"
if ! git status --porcelain=v1 --untracked-files=all -- "${vendor_dir}" >"${porcelain}"; then
  echo "❌ Failed to inspect vendored-skill status (git status)" >&2
  exit 1
fi

# The index is the proposed tree, so an index-only entry (`A `, `M `, `R `) is
# the canonical regeneration a commit is about to record. Real drift is anything
# the worktree disagrees on after sync: a nonblank worktree column, which also
# covers every `??` untracked regeneration.
drift="${work_dir}/drift.txt"
drift_status=0
grep -E '^.[^ ] ' "${porcelain}" >"${drift}" || drift_status=$?
if [ "${drift_status}" -ge 2 ]; then
  echo "❌ Failed to filter vendored-skill status (grep exit ${drift_status})" >&2
  exit "${drift_status}"
fi
drift_count="$(wc -l <"${drift}")"
status_count="$(wc -l <"${porcelain}")"

echo "ℹ️ Vendored-skill status entries: ${status_count}"
echo "ℹ️ Vendored-skill drift entries: ${drift_count}"
if [ "${drift_count}" -ne 0 ]; then
  echo "❌ Vendored skills are stale; re-run ./scripts/local/skills-sync.sh and stage the result:" >&2
  cat "${drift}" >&2
  exit 1
fi

echo "✅ Vendored skills are fresh"
