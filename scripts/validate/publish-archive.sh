#!/usr/bin/env bash
# Assert the PUBLISHED ARCHIVE is complete: every Dart source under the member's
# lib/ reaches pub.dev, and every symbol the public barrel re-exports resolves
# inside the archive.
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
# The defect survived a green analyze, a green test suite and a green
# `pub publish --dry-run` for one reason: all three ran against the WORKING TREE,
# where the file is present. Only the ARCHIVE is missing it. `dart analyze` never
# compiles hosted dependencies, so a consumer's analyze stays green too — the
# breakage only appears when something actually compiles the graph.
#
# So this gate asserts on the archive's own file list, printed as VALUES, and
# refuses on an empty result. A dry-run that exits 0 is not evidence that the
# archive contains anything in particular.
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_api_engine"
cd "${member_dir}"

listing="$(mktemp)"
trap 'rm -f "${listing}"' EXIT

# `--dry-run` prints the files it WOULD upload. Capture its own rc directly: piped
# into anything, we would read the pipe's status instead and a hard failure would
# look green.
rc=0
flutter pub publish --dry-run >"${listing}" 2>&1 || rc=$?
if [ "${rc}" -ne 0 ]; then
  cat "${listing}" >&2
  echo "❌ flutter pub publish --dry-run failed (rc=${rc})" >&2
  exit 1
fi

# Enumerate what SHOULD ship from git's own structured output rather than a shell
# glob: a glob over a filename list is a pattern match and fails silently on
# encoding, and git octal-quotes non-ASCII names.
expected="$(mktemp)"
trap 'rm -f "${listing}" "${expected}"' EXIT
git ls-files -z -- 'lib/**/*.dart' 'lib/*.dart' | tr '\0' '\n' | sort -u >"${expected}"

expected_count="$(wc -l <"${expected}")"
echo "→ ${expected_count} tracked Dart sources under ${member_dir}/lib"
if [ "${expected_count}" -eq 0 ]; then
  echo "❌ REFUSING: no tracked lib/ sources found — wrong directory or empty package" >&2
  exit 1
fi

missing=0
while IFS= read -r f; do
  # The dry-run listing indents each path; match the path as a whole field.
  if ! grep -qE "(^|[[:space:]])${f}([[:space:]]|$)" "${listing}"; then
    echo "   NOT IN ARCHIVE: ${f}" >&2
    missing=$((missing + 1))
  fi
done <"${expected}"

echo "→ sources missing from the archive: ${missing} (must be 0)"
if [ "${missing}" -ne 0 ]; then
  echo "❌ the published archive would OMIT ${missing} of ${expected_count} lib/ sources." >&2
  echo "   Check ${member_dir}/.pubignore for an UNANCHORED directory pattern: a bare" >&2
  echo "   'config/' excludes lib/src/config/ too. Anchor it as '/config/'." >&2
  exit 1
fi

# Second, differently-shaped check: every relative path the public barrels export
# or import must exist on disk AND be in the archive. This is the check that
# would have caught the auth-engine defect from the other direction — a dangling
# export is detectable without knowing which .pubignore rule caused it.
dangling=0
checked=0
for barrel in lib/diene_api_engine.dart lib/test_helper.dart; do
  [ -f "${barrel}" ] || {
    echo "❌ missing barrel: ${barrel}" >&2
    exit 1
  }
  while IFS= read -r rel; do
    checked=$((checked + 1))
    target="lib/${rel}"
    if [ ! -f "${target}" ]; then
      echo "   DANGLING in ${barrel}: ${rel} (no such file)" >&2
      dangling=$((dangling + 1))
      continue
    fi
    if ! grep -qE "(^|[[:space:]])${target}([[:space:]]|$)" "${listing}"; then
      echo "   EXPORTED BUT NOT SHIPPED in ${barrel}: ${target}" >&2
      dangling=$((dangling + 1))
    fi
  done < <(grep -oE "^(export|import) '(src/[^']+)'" "${barrel}" | sed -E "s/^(export|import) '//; s/'$//")
done

echo "→ ${checked} relative barrel references checked, ${dangling} dangling or unshipped (must be 0)"
if [ "${checked}" -eq 0 ]; then
  echo "❌ REFUSING: parsed zero relative references out of the barrels — the parse broke" >&2
  exit 1
fi
[ "${dangling}" -eq 0 ] || exit 1

echo "✅ published archive is complete: ${expected_count} lib/ sources present, ${checked} barrel references resolve and ship"
