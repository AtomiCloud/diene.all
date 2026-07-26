#!/usr/bin/env bash
set -euo pipefail

# skills-freshness gates the committed dependency-skill tree.
#
#   - With the enumerating toolchain available (normal dev shell, pls lint, CI)
#     it REGENERATES the tree and proves the commit matches, failing on both
#     tracked drift and scoped untracked output.
#   - Without Go it cannot regenerate. Ordinary missing-Go is a hard failure with
#     no mutation. The ONE exception is the offline Nix pre-commit builder, whose
#     restricted hook PATH omits go: there (and only there, detected via
#     NIX_BUILD_TOP) it honestly PRESERVES and verifies the already-committed
#     tree against the module set declared in go.mod, without regenerating or
#     wiping it.

vendor_dir=".claude/skills/vendor"
skills_go="${DIENE_SKILLS_GO:-$(command -v go 2>/dev/null || true)}"

if [ -x "${skills_go}" ]; then
  bash scripts/local/skills-sync.sh
  # Fail on BOTH tracked changes and scoped untracked output. A plain `git diff`
  # ignores newly generated but never-added skill files, so check untracked output
  # separately. Purely-staged additions are tolerated, so the very commit that
  # introduces the tree passes while a regenerated file that diverges from the
  # index or was never added still fails.
  tracked_drift="$(git diff --name-only -- "${vendor_dir}")"
  untracked="$(git ls-files --others --exclude-standard -- "${vendor_dir}")"
  if [ -n "${tracked_drift}${untracked}" ]; then
    echo "❌ Vendored skills are stale; re-run scripts/local/skills-sync.sh and commit the result:" >&2
    [ -n "${tracked_drift}" ] && echo "  modified: ${tracked_drift}" >&2
    [ -n "${untracked}" ] && echo "  untracked: ${untracked}" >&2
    exit 1
  fi
  echo "✅ Vendored skills are fresh"
  exit 0
fi

if [ -z "${NIX_BUILD_TOP:-}" ]; then
  # Ordinary missing-Go environment: a Go module must be able to regenerate to be
  # gated. Fail closed without touching the committed tree.
  echo "❌ skills-freshness: Go is required to verify dependency skills; set DIENE_SKILLS_GO to an absolute go path" >&2
  exit 1
fi

# Offline Nix builder: preserve and verify the committed tree. First reject any
# tracked or scoped-untracked drift with the same worktree/index checks the
# Go-enabled path uses (git diff compares the work tree to the index, so it holds
# even when the git-hooks checkout only staged the source with no commit). Without
# a git work tree there is nothing to verify against, so fail closed rather than
# silently claim the tree was preserved.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ skills-freshness: no git work tree to verify the committed vendor tree against (Go unavailable)" >&2
  exit 1
fi
tracked_drift="$(git diff --name-only -- "${vendor_dir}")"
untracked="$(git ls-files --others --exclude-standard -- "${vendor_dir}")"
if [ -n "${tracked_drift}${untracked}" ]; then
  echo "❌ skills-freshness: the committed vendor tree has uncommitted drift (Go unavailable, cannot regenerate):" >&2
  [ -n "${tracked_drift}" ] && echo "  modified: ${tracked_drift}" >&2
  [ -n "${untracked}" ] && echo "  untracked: ${untracked}" >&2
  exit 1
fi

# Then verify the committed tree against go.mod. The expected dependency set is
# every Diene module go.mod requires except the main module; each must have a
# committed, non-empty skill package, and no unexpected package may be present.
# Parse go.mod with sed/grep only: the restricted Nix builder PATH has no awk.
main_module="$(sed -n 's/^module[[:space:]]\{1,\}\([^[:space:]]*\).*/\1/p' go.mod | head -1)"
expected="$(grep -oE 'github\.com/AtomiCloud/diene[._-][A-Za-z0-9._-]+' go.mod | sort -u)"

missing=""
declare -A is_expected=()
while IFS= read -r module; do
  [ -n "${module}" ] || continue
  [ "${module}" = "${main_module}" ] && continue
  package="$(basename "${module}")"
  is_expected["${package}"]=1
  if ! find "${vendor_dir}/${package}" -type f -name 'SKILL.md' -print -quit 2>/dev/null | grep -q .; then
    missing="${missing} ${package}"
  fi
done <<<"${expected}"

unexpected=""
for entry in "${vendor_dir}"/*/; do
  [ -d "${entry}" ] || continue
  package="$(basename "${entry}")"
  [ -n "${is_expected[${package}]:-}" ] || unexpected="${unexpected} ${package}"
done

if [ -n "${missing}" ] || [ -n "${unexpected}" ]; then
  echo "❌ skills-freshness: committed vendor tree does not match go.mod's Diene dependencies (Go unavailable, cannot regenerate)" >&2
  [ -n "${missing}" ] && echo "  missing skills for:${missing}" >&2
  [ -n "${unexpected}" ] && echo "  unexpected packages:${unexpected}" >&2
  exit 1
fi

echo "✅ Vendored skills preserved (Go unavailable in Nix builder; verified the committed tree against go.mod, did not regenerate)"
