#!/usr/bin/env bash
set -euo pipefail

# R-E19a acceptance sweep (S27 style): the final diff vs the TRUE parent must
# contain ONLY node-intended diene_core_utils content and ZERO flutter-base
# identity.
#
# Every check prints the VALUE it compared. A guard whose PASS branch is reached
# by a command producing no output is not a guard, so the counts are printed and
# asserted rather than inferred from an exit status.
#
# Usage: scripts/validate/r-e19a-sweep.sh [<true-parent-ref>] [<head-ref>]

TRUE_PARENT="${1:-9a2e5bffc1e4ff36d259c1abc2b5021a7b7bca87}"
HEAD_REF="${2:-HEAD}"
QUARANTINE='refs/quarantine/lib/dart/core-utils/pre-r-e19a-416ad9b'
OLD_TIP='416ad9b615963435c291ec86485c8cf0f549b5c1'

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

fail=0
note() { printf '%s\n' "$*"; }
bad() {
  printf '❌ %s\n' "$*" >&2
  fail=1
}

note "→ R-E19a sweep: ${HEAD_REF} vs true parent ${TRUE_PARENT}"
note "  true parent  : $(git rev-parse "${TRUE_PARENT}")"
note "  head         : $(git rev-parse "${HEAD_REF}")"

# 1. Custody: the quarantined ref must still resolve to the old tip. ------------
note '→ R-E1 custody of the pre-transplant ref'
if ! git rev-parse --verify --quiet "${QUARANTINE}" >/dev/null; then
  bad "quarantine ref ${QUARANTINE} is absent; prior work custody is broken"
else
  resolved="$(git rev-parse "${QUARANTINE}")"
  note "  ${QUARANTINE} -> ${resolved}"
  [ "${resolved}" = "${OLD_TIP}" ] || bad "quarantine ref does not resolve to ${OLD_TIP}"
fi

# 2. Lineage: the true parent must now be an ancestor. -------------------------
note '→ lineage'
if git merge-base --is-ancestor "${TRUE_PARENT}" "${HEAD_REF}"; then
  note "  ${TRUE_PARENT:0:9} IS an ancestor of ${HEAD_REF} (R-E19 base is family law: dart-lib)"
else
  bad "the true parent is NOT an ancestor of ${HEAD_REF}"
fi
if git merge-base --is-ancestor "${OLD_TIP}" "${HEAD_REF}" 2>/dev/null; then
  bad "the wrong-base tip ${OLD_TIP:0:9} is still an ancestor; this is not a transplant"
else
  note "  wrong-base tip ${OLD_TIP:0:9} is NOT an ancestor (content moved, not replayed)"
fi

# 3. Zero flutter-base identity in the final diff. -----------------------------
note '→ flutter-base identity in the diff vs the true parent'
mapfile -t changed < <(git -c core.quotePath=false diff --name-only "${TRUE_PARENT}" "${HEAD_REF}")
note "  changed paths: ${#changed[@]}"
if [ "${#changed[@]}" -eq 0 ]; then
  bad 'the diff is EMPTY; a sweep over nothing proves nothing'
fi

# The wrong parent's identity, enumerated from the frozen flutter-base commit the
# dispatch note named, rather than from a hand-written hunch.
FLUTTER_BASE='891c5c9bad5c81b5d1011ac75143489b927cee94'
residue_hits=0
if git cat-file -e "${FLUTTER_BASE}^{commit}" 2>/dev/null; then
  git -c core.quotePath=false ls-tree -r --name-only "${FLUTTER_BASE}" | LC_ALL=C sort >/tmp/.re19a-flutter
  git -c core.quotePath=false ls-tree -r --name-only "${TRUE_PARENT}" | LC_ALL=C sort >/tmp/.re19a-parent
  # Paths that exist in flutter-base and NOT in the true parent are the wrong
  # parent's own identity: none of them may appear in our tree.
  comm -23 /tmp/.re19a-flutter /tmp/.re19a-parent >/tmp/.re19a-residue
  note "  flutter-base-only paths to check: $(wc -l </tmp/.re19a-residue)"
  git -c core.quotePath=false ls-tree -r --name-only "${HEAD_REF}" | LC_ALL=C sort >/tmp/.re19a-head
  comm -12 /tmp/.re19a-residue /tmp/.re19a-head >/tmp/.re19a-found
  residue_hits="$(wc -l </tmp/.re19a-found)"
  note "  flutter-base identity paths present in HEAD: ${residue_hits}"
  if [ "${residue_hits}" -ne 0 ]; then
    bad 'wrong-parent identity survived the transplant:'
    sed 's/^/     /' /tmp/.re19a-found >&2
  fi
else
  bad "flutter-base commit ${FLUTTER_BASE} is unreachable; refusing to judge residue on missing data"
fi

# 4. The named residue surfaces are individually absent. -----------------------
# The dispatch note names these specifically, so they are asserted by name as a
# second, differently-shaped check on top of the set comparison above.
note '→ the dispatch-note-named residue surfaces'
for path in \
  scripts/validate/cd-matrix.sh \
  scripts/validate/rebrand.sh \
  scripts/validate/signing-doctors.sh \
  .metadata \
  lpsm.yaml \
  slang.yaml \
  swagger_parser.yaml \
  pubspec.lock; do
  if git cat-file -e "${HEAD_REF}:${path}" 2>/dev/null; then
    bad "named flutter-base residue is still tracked: ${path}"
  else
    note "  absent: ${path}"
  fi
done
for dir in android ios assets openapi config/base.yaml lib/main.dart lib/app.dart; do
  if git -c core.quotePath=false ls-tree -r --name-only "${HEAD_REF}" -- "${dir}" | grep -q .; then
    bad "named flutter-base residue directory is still tracked: ${dir}"
  else
    note "  absent: ${dir}/"
  fi
done

# 5. The node-intended content IS present (a sweep must not pass on an empty tree).
note '→ node-intended content present'
present=0
for path in \
  packages/diene_core_utils/pubspec.yaml \
  packages/diene_core_utils/lib/diene_core_utils.dart \
  packages/diene_core_utils/lib/c0_temporal.dart \
  packages/diene_core_utils/lib/src/iana_zones.dart \
  packages/diene_core_utils/lib/src/c0_temporal_contract.dart \
  packages/diene_core_utils/lib/src/vfs_config.dart \
  packages/diene_core_utils/test/fixtures/c0/config.json \
  packages/diene_core_utils/skills/diene-core-utils-usage/SKILL.md \
  packages/diene_core_utils/doc/core_utils.md \
  third_party/iana-tzdata-2026b/version \
  contracts/c0/RELEASE.json; do
  if git cat-file -e "${HEAD_REF}:${path}" 2>/dev/null; then
    present=$((present + 1))
  else
    bad "node-intended content is MISSING: ${path}"
  fi
done
note "  node-intended anchors present: ${present}/11"

# 6. The wrong parent's sample package is gone and ours replaces it. -----------
note '→ workspace member identity'
if git -c core.quotePath=false ls-tree -r --name-only "${HEAD_REF}" -- packages/diene_dart_lib | grep -q .; then
  bad "the parent's sample package packages/diene_dart_lib is still tracked"
else
  note '  absent: packages/diene_dart_lib/ (parent sample replaced, R-E19a sanctioned deletion)'
fi
members="$(git -c core.quotePath=false ls-tree -d --name-only "${HEAD_REF}" -- packages | wc -l)"
note "  workspace members: ${members}"
[ "${members}" -eq 1 ] || bad "expected exactly one workspace member, found ${members}"

# 7. Package identity, by STRUCTURED QUERY rather than by name pattern. -------
#
# An earlier revision of this check grepped the whole tree for `diene_interfaces`
# and called every hit residue. That was wrong, and wrong in the exact way the
# "the triage tool is itself a gate" ruling describes: `diene_interfaces` is a
# DECLARED DEPENDENCY of this package — the R-E12 seam — so naming it is required,
# not leftover. A name pattern cannot separate "this package is mis-identified as
# diene_interfaces" from "this package imports diene_interfaces", so the identity
# check asks the MANIFESTS what the package is called instead of asking grep.
note '→ package identity (structured manifest queries)'
identity_checks=0
expect_yq() { # <file> <yq-expression> <expected>
  local file="$1" expr="$2" want="$3" got
  got="$(yq -r "${expr}" "${file}")"
  identity_checks=$((identity_checks + 1))
  note "  ${file} ${expr} = ${got}"
  [ "${got}" = "${want}" ] || bad "expected '${want}', got '${got}' for ${expr} in ${file}"
}
expect_yq pubspec.yaml '.name' 'diene_core_utils_workspace'
expect_yq pubspec.yaml '.workspace | join(",")' 'packages/diene_core_utils'
expect_yq packages/diene_core_utils/pubspec.yaml '.name' 'diene_core_utils'
expect_yq packages/diene_core_utils/pubspec.yaml '.repository' \
  'https://github.com/AtomiCloud/diene.dart_core_utils'
expect_yq atomi_release.yaml \
  '[.plugins[].config.changelogFile | select(. != null)] | join(",")' \
  'packages/diene_core_utils/CHANGELOG.md'
expect_yq codecov.yml '.flags.unit.paths | join(",")' 'packages/diene_core_utils/lib/src'
note "  identity assertions made: ${identity_checks}"
[ "${identity_checks}" -eq 6 ] || bad "expected 6 identity assertions, made ${identity_checks}"

# 8. The WRONG PARENT's package name must be gone as an identifier. ------------
# Unlike diene_interfaces, `diene_dart_lib` is not a dependency of anything here,
# so any surviving mention is genuine residue. This script must itself name the
# string in order to search for it, so it is the one allowed occurrence and is
# excluded by PATH, with the exclusion printed rather than silently applied.
note '→ the wrong parent package name as an identifier'
SELF='scripts/validate/r-e19a-sweep.sh'
mapfile -t sample_hits < <(
  git grep -I -l -E 'diene_dart_lib|diene-dart-lib' "${HEAD_REF}" -- . 2>/dev/null |
    sed "s|^${HEAD_REF}:||" | grep -v -x "${SELF}" || true
)
note "  files naming diene_dart_lib (excluding ${SELF}): ${#sample_hits[@]}"
if [ "${#sample_hits[@]}" -ne 0 ]; then
  bad 'the parent sample package name survives as an identifier:'
  printf '     %s\n' "${sample_hits[@]}" >&2
fi
# Positive control: the grep must be able to find the string it searches for, or a
# zero above would mean "the check is broken", not "the tree is clean".
self_hits="$(git grep -I -c -E 'diene_dart_lib' "${HEAD_REF}" -- "${SELF}" 2>/dev/null | sed 's/.*://' || echo 0)"
note "  positive control — occurrences inside ${SELF}: ${self_hits}"
[ "${self_hits}" -gt 0 ] || bad 'the diene_dart_lib grep found nothing even in this script; the check is not working'

# 9. diene_interfaces mentions are legitimate BECAUSE it is a declared dep. ----
note '→ diene_interfaces is a declared dependency, so its mentions are expected'
iface_constraint="$(yq -r '.dependencies.diene_interfaces // "ABSENT"' packages/diene_core_utils/pubspec.yaml)"
iface_mentions="$(git grep -I -l -E 'diene_interfaces' "${HEAD_REF}" -- . 2>/dev/null | wc -l)"
note "  declared constraint: ${iface_constraint}"
note "  files referencing it: ${iface_mentions}"
[ "${iface_constraint}" != 'ABSENT' ] || bad 'diene_interfaces is referenced but not declared as a dependency'
[ "${iface_mentions}" -gt 0 ] || bad 'diene_interfaces is declared but never used; the R-E12 seam is missing'

note ''
if [ "${fail}" -ne 0 ]; then
  note "❌ R-E19a sweep FAILED"
  exit 1
fi
note "✅ R-E19a sweep PASSED: ${#changed[@]} changed paths vs ${TRUE_PARENT:0:9}, ${residue_hits} flutter-base identity paths, ${present}/11 node anchors, ${members} workspace member, ${identity_checks}/6 manifest identity assertions, ${#sample_hits[@]} wrong-parent-name files, diene_interfaces ${iface_constraint} across ${iface_mentions} files"
