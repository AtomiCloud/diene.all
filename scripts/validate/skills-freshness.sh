#!/usr/bin/env bash
set -euo pipefail

bash scripts/local/skills-sync.sh
git diff --exit-code -- .claude/skills/vendor

if [ -f go.mod ] && command -v go >/dev/null 2>&1; then
  while IFS=$'\t' read -r module module_dir; do
    [ -n "${module_dir}" ] || continue
    skills_dir="${module_dir}/skills"
    [ -d "${skills_dir}" ] || continue
    package="$(basename "${module}")"
    vendored=".claude/skills/vendor/${package}"
    if [ ! -d "${vendored}" ] || [ -z "$(find "${vendored}" -type f -print -quit)" ]; then
      echo "❌ Installed module ${module} ships skills, but ${vendored} is absent or empty" >&2
      exit 1
    fi
  done < <(go list -m -json all | jq -r 'select(.Main != true) | select(.Path | test("(^|/)diene[._-]")) | [.Path, .Dir] | @tsv')
elif [ -f go.mod ]; then
  echo "⚠️ Go unavailable; independent module oracle deferred to CI setup/direct validation" >&2
fi

echo "✅ Vendored skills are fresh"
