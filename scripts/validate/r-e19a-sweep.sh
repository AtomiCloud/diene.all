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

# 7. No stale identity strings anywhere in the tree. --------------------------
note '→ residual package-identity strings'
stale="$(git grep -I -l -E 'diene_interfaces|diene-interfaces|diene_dart_lib|diene-dart-lib' "${HEAD_REF}" -- . 2>/dev/null | wc -l)"
fresh="$(git grep -I -l -E 'diene_core_utils|diene-core-utils' "${HEAD_REF}" -- . 2>/dev/null | wc -l)"
note "  files naming a FOREIGN package identity: ${stale}"
note "  files naming THIS package identity:     ${fresh}"
[ "${stale}" -eq 0 ] || {
  bad 'foreign package identity survives:'
  git grep -I -n -E 'diene_interfaces|diene-interfaces|diene_dart_lib|diene-dart-lib' "${HEAD_REF}" -- . | sed 's/^/     /' >&2
}
# Positive control: if the grep itself were broken, this would also read 0.
[ "${fresh}" -gt 0 ] || bad 'the identity grep found ZERO mentions of this package; the check is not working'

note ''
if [ "${fail}" -ne 0 ]; then
  note "❌ R-E19a sweep FAILED"
  exit 1
fi
note "✅ R-E19a sweep PASSED: ${#changed[@]} changed paths vs ${TRUE_PARENT:0:9}, ${residue_hits} flutter-base identity paths, ${present}/11 node anchors, ${members} workspace member, ${stale} foreign identity files, ${fresh} own-identity files"
