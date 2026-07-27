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
  # The freshness gate needs a SUBJECT: a `git diff` over a path with nothing
  # tracked under it compares zero files and can never fail (#16 DEFECT B).
  # .gitkeep only keeps the directory alive; it can never witness stale content.
  subjects_status=0
  subjects="$(git ls-files -- "${vendor_dir}" | grep -F -x -v "${vendor_dir}/.gitkeep")" || subjects_status=$?
  if [ "${subjects_status}" -ge 2 ]; then
    echo "❌ Failed to filter tracked vendored skills (grep exit ${subjects_status})" >&2
    exit "${subjects_status}"
  fi
  subject_count="$(printf %s"${subjects}" | grep -c . || true)"
  echo "ℹ️ Tracked vendored-skill subjects: ${subject_count}"
  if [ "${subject_count}" -eq 0 ]; then
    echo "❌ No tracked subject under ${vendor_dir}; the freshness gate would pass vacuously" >&2
    exit 1
  fi
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

# Offline Nix builder: preserve and verify the committed tree. Without a git work
# tree there is nothing to verify against, so fail closed rather than silently
# claim the tree was preserved.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ skills-freshness: no git work tree to verify the committed vendor tree against (Go unavailable)" >&2
  exit 1
fi

# Reject work-tree drift against the index for the vendor tree AND go.mod. go.mod
# is an INPUT to the verification below (it names the expected dependency set), so
# it has to be as trustworthy as the tree it is used to check.
tracked_drift="$(git diff --name-only -- "${vendor_dir}" go.mod)"
untracked="$(git ls-files --others --exclude-standard -- "${vendor_dir}")"
if [ -n "${tracked_drift}${untracked}" ]; then
  echo "❌ skills-freshness: the committed vendor tree has uncommitted drift (Go unavailable, cannot regenerate):" >&2
  [ -n "${tracked_drift}" ] && echo "  modified: ${tracked_drift}" >&2
  [ -n "${untracked}" ] && echo "  untracked: ${untracked}" >&2
  exit 1
fi

# A work-tree comparison alone only proves the tree matches the INDEX. Content
# that was altered and staged matches its index entry, so without this check an
# edited SKILL.md or a rewritten go.mod dependency set would pass as "committed"
# whenever the caller can set NIX_BUILD_TOP. Whenever the checkout has a HEAD,
# require the index to match it too. A HEAD-less checkout is the intentional
# git-hooks/Nix staged case, which has no committed state to compare against and
# is verified by the dependency-set check below.
if git rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
  staged_drift="$(git diff --cached --name-only HEAD -- "${vendor_dir}" go.mod)"
  if [ -n "${staged_drift}" ]; then
    echo "❌ skills-freshness: staged content differs from HEAD (Go unavailable, cannot regenerate):" >&2
    while IFS= read -r path; do
      echo "  staged: ${path}" >&2
    done <<<"${staged_drift}"
    exit 1
  fi
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
