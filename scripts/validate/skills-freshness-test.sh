#!/usr/bin/env bash
set -euo pipefail

# Isolated behavioral tests for scripts/local/skills-sync.sh and
# scripts/validate/skills-freshness.sh. Each case builds a throwaway git repo with
# a stub `go`, a stub module cache, and a controlled vendor tree, then asserts the
# exit code and whether the committed tree was mutated. Covers: full-Go (with main
# excluded), missing-Go (populated and empty, proving no mutation), jq failure,
# partial-input, stale-tracked, new-untracked, and the Nix-builder preserve
# fallback (complete, incomplete, drift, and a HEAD-less staged checkout).

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
sync_src="${repo_root}/scripts/local/skills-sync.sh"
fresh_src="${repo_root}/scripts/validate/skills-freshness.sh"

tmp="$(mktemp -d)"
trap 'chmod -R u+w "${tmp}" 2>/dev/null || true; rm -rf "${tmp}"' EXIT
failures=0

# A controlled tool directory with everything the scripts need EXCEPT go, so
# missing-Go is simulated honestly while git/jq/coreutils still resolve.
toolbin="${tmp}/toolbin"
mkdir -p "${toolbin}"
for tool in bash env sh git jq sed grep sort head basename dirname find mktemp chmod rm rmdir touch cp mkdir mv tr cat rg realpath sha256sum; do
  path="$(command -v "${tool}" 2>/dev/null || true)"
  [ -n "${path}" ] && ln -sf "${path}" "${toolbin}/${tool}"
done

pass() { echo "  ✅ $1"; }
fail() {
  echo "  ❌ $1" >&2
  failures=$((failures + 1))
}
expect_ok() { if [ "$1" = 0 ]; then pass "$2"; else fail "$2 (code=$1)"; fi; }
expect_fail() { if [ "$1" != 0 ]; then pass "$2"; else fail "$2 (code=$1)"; fi; }

vendor() { echo "$1/.claude/skills/vendor"; }
snapshot() { (cd "$1" && find . | sort && find . -type f -exec sha256sum {} + 2>/dev/null | sort); }

new_repo() {
  local dir="${tmp}/$1" omit="${2:-}"
  mkdir -p "${dir}/scripts/local" "${dir}/scripts/validate" "${dir}/.claude/skills/vendor"
  cp "${sync_src}" "${dir}/scripts/local/skills-sync.sh"
  cp "${fresh_src}" "${dir}/scripts/validate/skills-freshness.sh"
  touch "${dir}/.claude/skills/vendor/.gitkeep"

  mkdir -p "${dir}/cache/diene.go-core-utils/skills/core-usage"
  printf 'core skill\n' >"${dir}/cache/diene.go-core-utils/skills/core-usage/SKILL.md"
  if [ "${omit}" != "omit" ]; then
    mkdir -p "${dir}/cache/diene.go-errors-problems/skills/errors-usage"
    printf 'errors skill\n' >"${dir}/cache/diene.go-errors-problems/skills/errors-usage/SKILL.md"
  else
    mkdir -p "${dir}/cache/diene.go-errors-problems"
  fi

  cat >"${dir}/go.mod" <<EOF
module github.com/AtomiCloud/diene.example

go 1.26.0

require (
	github.com/AtomiCloud/diene.go-core-utils v1.0.0
	github.com/AtomiCloud/diene.go-errors-problems v1.0.0
)
EOF

  cat >"${dir}/stubgo" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "list" ]; then
  cat <<JSON
{"Path":"github.com/AtomiCloud/diene.example","Main":true,"Dir":"${dir}"}
{"Path":"github.com/AtomiCloud/diene.go-core-utils","Dir":"${dir}/cache/diene.go-core-utils"}
{"Path":"github.com/AtomiCloud/diene.go-errors-problems","Dir":"${dir}/cache/diene.go-errors-problems"}
JSON
fi
EOF
  chmod +x "${dir}/stubgo"

  git -C "${dir}" init -q
  git -C "${dir}" config user.email t@t.t
  git -C "${dir}" config user.name t
  echo "${dir}"
}

seed() {
  mkdir -p "$1/.claude/skills/vendor/$2"
  printf '%s\n' "$4" >"$1/.claude/skills/vendor/$2/$3"
}

commit_all() { git -C "$1" add -A && git -C "$1" commit -qm snapshot; }
stage_all() { git -C "$1" add -A; }

run() {
  local dir="$1" script="$2"
  shift 2
  local code=0
  (cd "${dir}" && env -i HOME="${HOME}" PATH="${toolbin}" "$@" bash "${script}" >/dev/null 2>&1) || code=$?
  echo "${code}"
}

echo "skills machinery behavioral tests:"

# 1. full-Go: sync regenerates the deps AND excludes the main module.
dir="$(new_repo full-go)"
code="$(run "${dir}" scripts/local/skills-sync.sh "DIENE_SKILLS_GO=${dir}/stubgo")"
if [ "${code}" = 0 ] &&
  [ -f "$(vendor "${dir}")/diene.go-core-utils/core-usage/SKILL.md" ] &&
  [ -f "$(vendor "${dir}")/diene.go-errors-problems/errors-usage/SKILL.md" ] &&
  [ ! -e "$(vendor "${dir}")/diene.example" ]; then
  pass "full-Go regenerates deps and excludes the main module"
else
  fail "full-Go should vendor deps only, not the main module (code=${code})"
fi

# 2. missing-Go populated: sync fails with NO mutation of the tree.
dir="$(new_repo missing-populated)"
seed "${dir}" diene.go-core-utils SKILL.md committed
before="$(snapshot "$(vendor "${dir}")")"
code="$(run "${dir}" scripts/local/skills-sync.sh)"
after="$(snapshot "$(vendor "${dir}")")"
if [ "${code}" != 0 ] && [ "${before}" = "${after}" ]; then
  pass "missing-Go populated fails with the tree byte-identical"
else
  fail "missing-Go populated must fail without mutation (code=${code})"
fi
expect_fail "$(run "${dir}" scripts/validate/skills-freshness.sh)" "missing-Go freshness fails (populated)"

# 3. missing-Go initially-empty: sync fails, tree stays exactly .gitkeep.
dir="$(new_repo missing-empty)"
before="$(snapshot "$(vendor "${dir}")")"
code="$(run "${dir}" scripts/local/skills-sync.sh)"
after="$(snapshot "$(vendor "${dir}")")"
if [ "${code}" != 0 ] && [ "${before}" = "${after}" ] && [ -f "$(vendor "${dir}")/.gitkeep" ]; then
  pass "missing-Go empty fails and retains .gitkeep unchanged"
else
  fail "missing-Go empty must fail without mutation (code=${code})"
fi
expect_fail "$(run "${dir}" scripts/validate/skills-freshness.sh)" "missing-Go freshness fails (empty)"

# 4. jq failure: an unparseable enumeration aborts before staging.
dir="$(new_repo jqfail)"
printf '#!/usr/bin/env bash\necho "not valid json"\n' >"${dir}/stubgo"
chmod +x "${dir}/stubgo"
before="$(snapshot "$(vendor "${dir}")")"
code="$(run "${dir}" scripts/local/skills-sync.sh "DIENE_SKILLS_GO=${dir}/stubgo")"
after="$(snapshot "$(vendor "${dir}")")"
if [ "${code}" != 0 ] && [ "${before}" = "${after}" ]; then
  pass "jq failure aborts before staging without mutation"
else
  fail "jq failure must abort before replacement (code=${code})"
fi

# 5. partial-input: a dependency without a skills directory fails before replacement.
dir="$(new_repo partial omit)"
printf 'sentinel\n' >"$(vendor "${dir}")/.sentinel"
code="$(run "${dir}" scripts/local/skills-sync.sh "DIENE_SKILLS_GO=${dir}/stubgo")"
if [ "${code}" != 0 ] && [ -f "$(vendor "${dir}")/.sentinel" ]; then
  pass "partial input fails before replacing the tree"
else
  fail "partial input should fail and leave the tree untouched (code=${code})"
fi

# 6. stale-tracked: a committed skill whose content diverges from regeneration.
dir="$(new_repo stale)"
seed "${dir}" diene.go-core-utils/core-usage SKILL.md STALE
seed "${dir}" diene.go-errors-problems/errors-usage SKILL.md "errors skill"
commit_all "${dir}"
expect_fail "$(run "${dir}" scripts/validate/skills-freshness.sh "DIENE_SKILLS_GO=${dir}/stubgo")" "stale tracked content fails freshness"

# 7. new-untracked: regeneration produces a dependency the commit lacks.
dir="$(new_repo untracked)"
seed "${dir}" diene.go-core-utils/core-usage SKILL.md "core skill"
commit_all "${dir}"
expect_fail "$(run "${dir}" scripts/validate/skills-freshness.sh "DIENE_SKILLS_GO=${dir}/stubgo")" "new untracked output fails freshness"

# 8. Nix-builder preserve (complete, committed): passes.
dir="$(new_repo preserve-ok)"
seed "${dir}" diene.go-core-utils/core-usage SKILL.md core
seed "${dir}" diene.go-errors-problems/errors-usage SKILL.md errors
commit_all "${dir}"
expect_ok "$(run "${dir}" scripts/validate/skills-freshness.sh "NIX_BUILD_TOP=/build")" "Nix-builder preserve verifies a complete committed tree"

# 9. Nix-builder preserve (complete, HEAD-less staged checkout): still passes.
dir="$(new_repo preserve-staged)"
seed "${dir}" diene.go-core-utils/core-usage SKILL.md core
seed "${dir}" diene.go-errors-problems/errors-usage SKILL.md errors
stage_all "${dir}"
expect_ok "$(run "${dir}" scripts/validate/skills-freshness.sh "NIX_BUILD_TOP=/build")" "Nix-builder preserve passes on a staged, un-committed checkout"

# 10. Nix-builder preserve (incomplete): a go.mod dependency is missing.
dir="$(new_repo preserve-missing)"
seed "${dir}" diene.go-core-utils/core-usage SKILL.md core
commit_all "${dir}"
expect_fail "$(run "${dir}" scripts/validate/skills-freshness.sh "NIX_BUILD_TOP=/build")" "Nix-builder preserve fails on an incomplete tree"

# 11. Nix-builder preserve rejects scoped-untracked drift.
dir="$(new_repo preserve-drift)"
seed "${dir}" diene.go-core-utils/core-usage SKILL.md core
seed "${dir}" diene.go-errors-problems/errors-usage SKILL.md errors
commit_all "${dir}"
printf 'stray\n' >"$(vendor "${dir}")/diene.go-core-utils/core-usage/EXTRA.md"
expect_fail "$(run "${dir}" scripts/validate/skills-freshness.sh "NIX_BUILD_TOP=/build")" "Nix-builder preserve rejects untracked drift"

# 12. Nix-builder preserve rejects ALTERED-AND-STAGED skill content on a normal
# committed checkout. The work tree matches the index here, so only an index
# against HEAD comparison catches it; without that, anyone able to set
# NIX_BUILD_TOP could pass off edited skills as committed.
dir="$(new_repo preserve-staged-skill)"
seed "${dir}" diene.go-core-utils/core-usage SKILL.md core
seed "${dir}" diene.go-errors-problems/errors-usage SKILL.md errors
commit_all "${dir}"
printf 'tampered\n' >"$(vendor "${dir}")/diene.go-core-utils/core-usage/SKILL.md"
stage_all "${dir}"
expect_fail "$(run "${dir}" scripts/validate/skills-freshness.sh "NIX_BUILD_TOP=/build")" "Nix-builder preserve rejects altered-and-staged skill content"

# 13. Nix-builder preserve rejects a staged go.mod dependency-set rewrite: go.mod
# is the input naming the expected packages, so tampering with it must not pass.
dir="$(new_repo preserve-staged-gomod)"
seed "${dir}" diene.go-core-utils/core-usage SKILL.md core
seed "${dir}" diene.go-errors-problems/errors-usage SKILL.md errors
commit_all "${dir}"
sed 's#github.com/AtomiCloud/diene.go-errors-problems v1.0.0##' "${dir}/go.mod" >"${dir}/go.mod.next"
mv "${dir}/go.mod.next" "${dir}/go.mod"
stage_all "${dir}"
expect_fail "$(run "${dir}" scripts/validate/skills-freshness.sh "NIX_BUILD_TOP=/build")" "Nix-builder preserve rejects a staged go.mod dependency-set rewrite"

# 14. Nix-builder preserve rejects unstaged go.mod tampering too.
dir="$(new_repo preserve-dirty-gomod)"
seed "${dir}" diene.go-core-utils/core-usage SKILL.md core
seed "${dir}" diene.go-errors-problems/errors-usage SKILL.md errors
commit_all "${dir}"
printf '\n// tampered\n' >>"${dir}/go.mod"
expect_fail "$(run "${dir}" scripts/validate/skills-freshness.sh "NIX_BUILD_TOP=/build")" "Nix-builder preserve rejects unstaged go.mod tampering"

if [ "${failures}" -ne 0 ]; then
  echo "❌ ${failures} skills machinery test(s) failed" >&2
  exit 1
fi
echo "✅ skills machinery behavioral tests passed"
