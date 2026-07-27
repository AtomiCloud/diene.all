#!/usr/bin/env bash
# Assert the PUBLISHED ARCHIVE would be COMPLETE: every file the package must
# ship survives .pubignore, every dev/CI path is still excluded, and every symbol
# the public barrels re-export resolves to a file that ships.
#
# WHY THIS EXISTS. Both published diene_auth_engine releases (1.0.0 and 1.0.1)
# are structurally unusable and nothing caught it. `.pubignore` carried a bare
# `config/` pattern; .pubignore uses gitignore semantics, so that matches a
# directory named `config` at ANY DEPTH, and it silently removed
# `lib/src/config/auth_engine_config.dart` from the archive — while
# `lib/diene_auth_engine.dart` still `export`s that path and two more files
# `import` it. Every consumer of the barrel therefore fails to COMPILE with
# "Error: Type 'AuthEngineConfig' not found.", and publication is irreversible.
#
# The defect survived a green analyze, a green test suite AND a green
# `pub publish --dry-run`, because all three run against the WORKING TREE where
# the file is present. Only the ARCHIVE lacks it. `dart analyze` never compiles
# hosted dependencies, so a consumer's analyze stays green as well — the breakage
# appears only when something actually compiles the graph.
#
# SCOPE. This gate deliberately does NOT run `pub publish --dry-run`: that is
# already covered by scripts/ci/package-validate.sh, and duplicating it here made
# this script unusable as a pre-commit hook. pub emits a warning for ANY modified
# checked-in file, so a dry-run assertion can only pass on a clean tree, whereas a
# hook by definition runs with modifications present. The check below is
# tree-state INDEPENDENT: it asks git's ignore engine about path semantics, which
# is the same semantics pub applies to .pubignore, so it is a structured query
# rather than a pattern match over human-readable output.
#
# ---------------------------------------------------------------------------
# CORRECTION, kept rather than overwritten because the error is instructive.
# The FIRST version proved completeness by grepping `pub publish --dry-run` output
# for each repo-relative path. That cannot work: the dry-run prints an indented
# TREE OF BASENAMES ("└── patterns.md (2 KB)"), so no path ever matched and the
# gate reported "the published archive would OMIT 22 of 22 lib/ sources" — every
# file, which is the signature of a broken checker rather than a real finding. It
# was caught by the shape of its own failure, never by a passing run.
#
# Validated against KNOWN ANSWERS in both directions before being relied on:
#   unanchored `config/` -> lib/src/config/x.dart IS ignored (reproduces the
#                           auth-engine defect exactly)
#   anchored  `/config/` -> lib/src/config/x.dart is NOT ignored, while
#                           config/base.yaml still IS.
# ---------------------------------------------------------------------------
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_api_engine"
pubignore="${member_dir}/.pubignore"

[ -f "${pubignore}" ] || {
  echo "❌ missing ${pubignore}" >&2
  exit 1
}

scratch="$(mktemp -d)"
expected="$(mktemp)"
trap 'rm -rf "${scratch}" "${expected}"' EXIT

# Build a scratch repo whose .gitignore IS the .pubignore, then ask git. Paths do
# not need to exist there (`--no-index`), so this is a pure semantics query and
# cannot be perturbed by the state of the working tree.
git init -q "${scratch}"
cp "${pubignore}" "${scratch}/.gitignore"

# THE VERDICT COMES FROM THE PLAIN FORM ONLY.
#
# `git check-ignore -v` EXITS 0 ON A NEGATED MATCH: the -v form answers "a
# pattern matched, here is the line", and a `!negation` IS a match. So rc=0 from
# -v does NOT mean the path is excluded. Verified on a synthetic control with
# known answers before relying on it — with `.gitignore` = {`result-*`,
# `!result-keep.json`}:
#
#   result-drop.json   plain rc=0   -v rc=0   -> excluded
#   result-keep.json   plain rc=1   -v rc=0   -> NOT excluded  <-- the trap
#   unrelated.txt      plain rc=1   -v rc=1   -> not matched
#
# -v NAMES THE LINE; THE PLAIN FORM GIVES THE VERDICT. This helper is
# deliberately the only thing that decides, and it uses `-q` (plain). `-v` is
# used below purely to report WHICH rule fired, and only after this function has
# already returned a positive verdict — so a negation can never be reported as an
# exclusion. (Credit: peer `noel` circulated this correction after prescribing -v
# as the instrument; the hazard was re-measured here rather than taken on trust.)
ignored() { # ignored <path-relative-to-member>
  (cd "${scratch}" && git check-ignore --no-index -q -- "$1")
}

# --- 1. no must-ship path may be excluded ---------------------------------
# Enumerate from git's own structured output, never a shell glob: a glob over a
# filename list is a pattern match and fails silently on encoding, and git
# octal-quotes non-ASCII names.
git ls-files -z -- \
  "${member_dir}/lib" \
  "${member_dir}/example" \
  "${member_dir}/doc" \
  "${member_dir}/skills" \
  "${member_dir}/README.md" \
  "${member_dir}/CHANGELOG.md" \
  "${member_dir}/LICENSE" \
  "${member_dir}/pubspec.yaml" |
  tr '\0' '\n' |
  sed "s|^${member_dir}/||" |
  sort -u >"${expected}"

# DRILLED, because a guard nobody has watched fire is unproven rather than
# passing. Pointing `member_dir` at a directory that exists but holds only a
# `.pubignore` reaches this branch and it behaves correctly:
#   → 0 tracked must-ship paths under packages/diene_TMPTEST
#   ❌ REFUSING: enumerated zero must-ship paths …            (rc=1)
#
# A CORRECTION TO MYSELF is recorded here rather than silently dropped. I first
# added a second guard above this one, capturing a `git ls-files` rc on the theory
# that a bad pathspec would abort under errexit before this refusal could print.
# MEASURED: `git ls-files -- <nonexistent path>` exits **0**, so that guard could
# never fire — I introduced an unfalsifiable check while acting on a warning about
# unfalsifiable checks. It has been removed. The rc=2 that suggested it came from a
# mutated COPY of this script, not from this script. Test the premise, not the
# story that explains it.
expected_count="$(wc -l <"${expected}")"
echo "→ ${expected_count} tracked must-ship paths under ${member_dir}"
if [ "${expected_count}" -eq 0 ]; then
  echo "❌ REFUSING: enumerated zero must-ship paths — wrong directory or broken query" >&2
  exit 1
fi

excluded=0
while IFS= read -r rel; do
  if ignored "${rel}"; then
    reason="$( (cd "${scratch}" && git check-ignore --no-index -v -- "${rel}") | sed 's|^\.gitignore:|.pubignore:|')"
    echo "   EXCLUDED FROM ARCHIVE: ${rel}" >&2
    echo "     by ${reason}" >&2
    excluded=$((excluded + 1))
  fi
done <"${expected}"

echo "→ must-ship paths excluded by .pubignore: ${excluded} (must be 0)"
if [ "${excluded}" -ne 0 ]; then
  echo "❌ ${excluded} of ${expected_count} must-ship paths would be OMITTED from the archive." >&2
  echo "   The usual cause is an UNANCHORED directory pattern: a bare 'config/'" >&2
  echo "   matches lib/src/config/ too. Anchor it as '/config/'." >&2
  exit 1
fi

# --- 2. the exclusions must still work in the OTHER direction --------------
# An exclusion is two claims — this is excluded AND nothing else is. Checking only
# the first is how a narrow exclusion silently becomes a broad one.
must_exclude=(
  "test/unit/bridge_test.dart"
  "tool/deadcode_entrypoints.dart"
  "openapi/service.openapi.yaml"
  "swagger_parser.yaml"
)
kept_out=0
for rel in "${must_exclude[@]}"; do
  if ignored "${rel}"; then
    kept_out=$((kept_out + 1))
  else
    echo "   SHOULD NOT SHIP BUT WOULD: ${rel}" >&2
  fi
done
echo "→ dev/CI paths correctly excluded: ${kept_out}/${#must_exclude[@]} (must be ${#must_exclude[@]})"
[ "${kept_out}" -eq "${#must_exclude[@]}" ] || exit 1

# --- 3. every relative barrel reference resolves AND ships -----------------
# The check that would have caught the auth-engine defect from the other
# direction: a dangling export is detectable without knowing which rule caused it.
dangling=0
checked=0
for barrel in lib/diene_api_engine.dart lib/test_helper.dart; do
  [ -f "${member_dir}/${barrel}" ] || {
    echo "❌ missing barrel: ${member_dir}/${barrel}" >&2
    exit 1
  }
  while IFS= read -r rel; do
    checked=$((checked + 1))
    target="lib/${rel}"
    if [ ! -f "${member_dir}/${target}" ]; then
      echo "   DANGLING in ${barrel}: ${rel} (no such file)" >&2
      dangling=$((dangling + 1))
      continue
    fi
    if ignored "${target}"; then
      echo "   EXPORTED BUT EXCLUDED in ${barrel}: ${target}" >&2
      dangling=$((dangling + 1))
    fi
  done < <(grep -oE "^(export|import) '(src/[^']+)'" "${member_dir}/${barrel}" |
    sed -E "s/^(export|import) '//; s/'$//")
done

echo "→ ${checked} relative barrel references checked, ${dangling} dangling or excluded (must be 0)"
if [ "${checked}" -eq 0 ]; then
  echo "❌ REFUSING: parsed zero relative references out of the barrels — the parse broke" >&2
  exit 1
fi
[ "${dangling}" -eq 0 ] || exit 1

echo "✅ archive complete: ${expected_count} must-ship paths ship, ${checked} barrel references resolve, ${kept_out} dev paths excluded"
