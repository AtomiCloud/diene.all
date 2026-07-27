#!/usr/bin/env bash
set -euo pipefail

# R-E19a acceptance sweep (S27 style): the final diff vs the TRUE parent must
# contain ONLY node-intended diene_config content and ZERO flutter-base
# identity.
#
# Every check prints the VALUE it compared. A guard whose PASS branch is reached
# by a command producing no output is not a guard, so the counts are printed and
# asserted rather than inferred from an exit status.
#
# Usage: scripts/validate/r-e19a-sweep.sh [<true-parent-ref>] [<head-ref>]

TRUE_PARENT="${1:-796d0252fa94b14e2ec418fd9c70e3f75e792813}"
HEAD_REF="${2:-HEAD}"
QUARANTINE='refs/heads/quarantine/lib-dart-config-pre-r-e19a-20260726-ebde284'
OLD_TIP='ebde28470cefb5b53c8e65635d069ace2063bfb3'

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

# One private scratch directory with one cleanup trap. Fixed /tmp names let
# concurrent runs clobber each other's evidence and leave residue behind, which
# for an evidence-producing gate is itself a correctness problem.
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

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
# transplant audit named, rather than from a hand-written hunch.
FLUTTER_BASE='a836f1916b08d6bc74ef8bb2efe27904bdae0dfb'
residue_hits=0
if git cat-file -e "${FLUTTER_BASE}^{commit}" 2>/dev/null; then
  git -c core.quotePath=false ls-tree -r --name-only "${FLUTTER_BASE}" | LC_ALL=C sort >"${work}/flutter"
  git -c core.quotePath=false ls-tree -r --name-only "${TRUE_PARENT}" | LC_ALL=C sort >"${work}/parent"
  # Paths that exist in flutter-base and NOT in the true parent are the wrong
  # parent's own identity: none of them may appear in our tree.
  comm -23 "${work}/flutter" "${work}/parent" >"${work}/residue"
  note "  flutter-base-only paths to check: $(wc -l <"${work}/residue")"
  git -c core.quotePath=false ls-tree -r --name-only "${HEAD_REF}" | LC_ALL=C sort >"${work}/head"
  comm -12 "${work}/residue" "${work}/head" >"${work}/found"
  residue_hits="$(wc -l <"${work}/found")"
  note "  flutter-base identity paths present in HEAD: ${residue_hits}"
  if [ "${residue_hits}" -ne 0 ]; then
    bad 'wrong-parent identity survived the transplant:'
    sed 's/^/     /' "${work}/found" >&2
  fi
else
  bad "flutter-base commit ${FLUTTER_BASE} is unreachable; refusing to judge residue on missing data"
fi

# 4. The named residue surfaces are individually absent. -----------------------
# The audit names these specifically, so they are asserted by name as a second,
# differently-shaped check on top of the set comparison above.
#
# Every entry below is verified to exist in the OLD TIP and NOT in the true
# parent, so each absence is a real assertion. Paths the true parent legitimately
# owns are deliberately NOT listed: root `analysis_options.yaml` and `config/`
# are parent-owned surfaces that R-E19a retains, so demanding their absence would
# assert the opposite of the rule. The set comparison in step 3 already excludes
# them for the same reason.
note '→ the audit-named residue surfaces (old-tip-only, absent from the true parent)'
residue_named=0
for path in \
  pubspec.lock \
  .pubignore \
  CHANGELOG.md \
  LICENSE \
  .config/dart.coverage.yaml \
  scripts/validate/coverage.sh \
  scripts/validate/deadcode.sh \
  scripts/validate/dart-publish-version.sh \
  docs/developer/flutter-baseline.md \
  docs/developer/mobile-store-runbook.md \
  docs/developer/template-maintenance.md \
  docs/domain/identity.md \
  docs/standards/screen/index.md \
  docs/standards/form/index.md \
  docs/standards/frontend-ux/index.md \
  docs/standards/testing/languages/dart.md; do
  residue_named=$((residue_named + 1))
  if git cat-file -e "${HEAD_REF}:${path}" 2>/dev/null; then
    bad "named wrong-parent residue is still tracked: ${path}"
  else
    note "  absent: ${path}"
  fi
done
note "  named residue paths asserted absent: ${residue_named}"
[ "${residue_named}" -eq 16 ] || bad "expected 16 named residue assertions, made ${residue_named}"
# Root-level directories the old root-package layout and the Flutter base owned.
# `config/` is excluded on purpose: the true parent tracks config/action-trust.json.
for dir in android ios assets openapi lib test tool example \
  .claude/skills/frontend-ux-check .claude/skills/vision-loop .claude/skills/write-screen; do
  if git -c core.quotePath=false ls-tree -r --name-only "${HEAD_REF}" -- "${dir}" | grep -q .; then
    bad "named wrong-parent residue directory is still tracked at the ROOT: ${dir}"
  else
    note "  absent: ${dir}/"
  fi
done

# 5. The node-intended content IS present (a sweep must not pass on an empty tree).
note '→ node-intended content present'
anchors=(
  packages/diene_config/pubspec.yaml
  packages/diene_config/lib/diene_config.dart
  packages/diene_config/lib/c0_config.dart
  packages/diene_config/lib/config/app_config.dart
  packages/diene_config/lib/test_helper.dart
  packages/diene_config/test/fixtures/c0/config.json
  packages/diene_config/tool/gen_c0_projection.dart
  packages/diene_config/skills/diene-config-usage/SKILL.md
  packages/diene_config/doc/configuration.md
  contracts/c0/RELEASE.json
  .prettierignore
)
present=0
for path in "${anchors[@]}"; do
  if git cat-file -e "${HEAD_REF}:${path}" 2>/dev/null; then
    present=$((present + 1))
  else
    bad "node-intended content is MISSING: ${path}"
  fi
done
note "  node-intended anchors present: ${present}/${#anchors[@]}"
[ "${present}" -eq "${#anchors[@]}" ] || bad "expected ${#anchors[@]} node anchors, found ${present}"

# 6. The wrong parent's sample package is gone and ours replaces it. -----------
note '→ workspace member identity'
if git -c core.quotePath=false ls-tree -r --name-only "${HEAD_REF}" -- packages/diene_dart_lib | grep -q .; then
  bad "the parent's sample package packages/diene_dart_lib is still tracked"
else
  note '  absent: packages/diene_dart_lib/ (parent sample replaced, R-E19a sanctioned deletion)'
fi
# Enumerate the CHILDREN of packages/, not `packages` itself. The obvious
# `ls-tree -d -- packages` lists the single top-level `packages` directory, so it
# reports "1" no matter how many member directories are inside — it would stay
# green with a second package present. Listing `${HEAD_REF}:packages` asks the
# tree for its actual children, and both the count AND the exact singleton name
# are asserted, so neither an extra member nor a renamed one can slip through.
mapfile -t member_dirs < <(
  git -c core.quotePath=false ls-tree -d --name-only "${HEAD_REF}:packages" 2>/dev/null || true
)
members="${#member_dirs[@]}"
note "  workspace member directories under packages/: ${members} [${member_dirs[*]-}]"
[ "${members}" -eq 1 ] || bad "expected exactly one workspace member directory, found ${members}"
[ "${member_dirs[0]-}" = 'diene_config' ] || bad "the sole workspace member must be diene_config, found '${member_dirs[0]-none}'"
declared_members="$(git show "${HEAD_REF}:pubspec.yaml" | yq -r '.workspace | length')"
note "  workspace members declared in the root manifest: ${declared_members}"
[ "${declared_members}" -eq 1 ] || bad "expected exactly one declared member, found ${declared_members}"

# 7. Package identity, by STRUCTURED QUERY rather than by name pattern. -------
#
# A name pattern cannot separate "this package is mis-identified as X" from
# "this package DEPENDS on X" — diene_core_utils and diene_result are declared
# dependencies here, so naming them is required, not leftover. The identity
# check therefore asks the MANIFESTS what things are called instead of grep.
note '→ package identity (structured manifest queries)'
identity_checks=0
expect_yq() { # <file> <yq-expression> <expected>
  local file="$1" expr="$2" want="$3" got
  got="$(yq -r "${expr}" "${file}")"
  identity_checks=$((identity_checks + 1))
  note "  ${file} ${expr} = ${got}"
  [ "${got}" = "${want}" ] || bad "expected '${want}', got '${got}' for ${expr} in ${file}"
}
expect_yq pubspec.yaml '.name' 'diene_config_workspace'
expect_yq pubspec.yaml '.workspace | join(",")' 'packages/diene_config'
expect_yq packages/diene_config/pubspec.yaml '.name' 'diene_config'
expect_yq packages/diene_config/pubspec.yaml '.repository' \
  'https://github.com/AtomiCloud/diene.dart_config'
expect_yq atomi_release.yaml \
  '[.plugins[].config.changelogFile | select(. != null)] | join(",")' \
  'packages/diene_config/CHANGELOG.md'
expect_yq codecov.yml '.flags.unit.paths | join(",")' 'packages/diene_config/lib/src'
expect_yq codecov.yml '.flags.meta.paths | join(",")' 'packages/diene_config/lib/test_helper.dart'
note "  identity assertions made: ${identity_checks}"
[ "${identity_checks}" -eq 7 ] || bad "expected 7 identity assertions, made ${identity_checks}"

# 8. No Flutter identity in either manifest. ----------------------------------
#
# The surfaces that would carry Flutter identity into a manifest are: a
# dependency or dev_dependency NAMED flutter*, a dependency resolved from the
# `sdk: flutter` pseudo-source, and a top-level `flutter:` section. All three are
# emitted as plain lines and counted, rather than filtered inside yq: `select()`
# inside a yq-go array constructor does NOT filter, so the obvious one-expression
# form silently reports a hit for every manifest. The top-level key list is the
# reliable way to see a `flutter:` section, since no legitimate pubspec top-level
# key contains the substring.
flutter_surfaces() { # <manifest> -> one candidate string per line
  yq -r '
    [ (.dependencies // {} | to_entries[] | .key),
      (.dev_dependencies // {} | to_entries[] | .key),
      (.dependencies // {} | to_entries[] | select((.value | tag) == "!!map") | .value.sdk // ""),
      (.dev_dependencies // {} | to_entries[] | select((.value | tag) == "!!map") | .value.sdk // ""),
      (keys | .[])
    ] | .[]' "$1"
}
note '→ pure-Dart identity (R-E10): no Flutter package, sdk, or plugin surface'
# Positive control FIRST: a synthetic Flutter manifest must be detected, or a
# zero below would mean "the detector is broken", not "the tree is pure Dart".
control="$(mktemp)"
trap 'rm -f "${control}"' EXIT
printf 'name: control\nflutter:\n  uses-material-design: true\ndependencies:\n  flutter:\n    sdk: flutter\n' >"${control}"
control_hits="$(flutter_surfaces "${control}" | grep -ci flutter || true)"
note "  positive control — flutter-shaped entries in a synthetic Flutter manifest: ${control_hits}"
[ "${control_hits}" -gt 0 ] || bad 'the Flutter detector finds nothing even in a Flutter manifest; the check is not working'
flutter_hits=0
for manifest in pubspec.yaml packages/diene_config/pubspec.yaml; do
  n="$(flutter_surfaces "${manifest}" | grep -ci flutter || true)"
  note "  ${manifest}: flutter-shaped entries = ${n}"
  flutter_hits=$((flutter_hits + n))
done
[ "${flutter_hits}" -eq 0 ] || bad "Flutter identity survives in a manifest (${flutter_hits} entries)"

# 9. Hosted-only dependencies: no path deps anywhere. -------------------------
note '→ hosted-only dependency shape'
path_deps="$(yq -r '
  [ ((.dependencies // {}) + (.dev_dependencies // {})) | to_entries[]
    | select((.value | tag) == "!!map") | select(.value | has("path")) | .key ]
  | length' packages/diene_config/pubspec.yaml)"
note "  path dependencies in the member manifest: ${path_deps}"
[ "${path_deps}" -eq 0 ] || bad "path dependencies are forbidden; found ${path_deps}"
for manifest in pubspec.yaml packages/diene_config/pubspec.yaml; do
  ov="$(yq -r 'has("dependency_overrides")' "${manifest}")"
  note "  ${manifest} has dependency_overrides = ${ov}"
  [ "${ov}" = 'false' ] || bad "${manifest} must not carry dependency_overrides"
done

# 10. The WRONG PARENT's package name must be gone as an identifier. ----------
# Unlike the declared dependencies, `diene_dart_lib` is not a dependency of
# anything here, so any surviving mention is genuine residue. This script must
# itself name the string in order to search for it, so it is the one allowed
# occurrence and is excluded by PATH, with the exclusion printed rather than
# silently applied.
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

# 11. The declared dependencies are legitimate BECAUSE they are declared. -----
note '→ declared hosted dependencies are consumed, so their mentions are expected'
dep_mentions=0
for dep in diene_core_utils diene_problems diene_result yaml; do
  constraint="$(yq -r ".dependencies.${dep} // \"ABSENT\"" packages/diene_config/pubspec.yaml)"
  mentions="$(git grep -I -l -E "${dep}" "${HEAD_REF}" -- . 2>/dev/null | wc -l)"
  note "  ${dep}: constraint=${constraint} referenced in ${mentions} files"
  [ "${constraint}" != 'ABSENT' ] || bad "${dep} is referenced but not declared as a dependency"
  [ "${mentions}" -gt 0 ] || bad "${dep} is declared but never used; the R-E12 seam is missing"
  dep_mentions=$((dep_mentions + 1))
done
[ "${dep_mentions}" -eq 4 ] || bad "expected 4 dependency seam checks, made ${dep_mentions}"

note ''
if [ "${fail}" -ne 0 ]; then
  note "❌ R-E19a sweep FAILED"
  exit 1
fi
note "✅ R-E19a sweep PASSED: ${#changed[@]} changed paths vs ${TRUE_PARENT:0:9}, ${residue_hits} flutter-base identity paths, ${present}/${#anchors[@]} node anchors, ${members} workspace member (${declared_members} declared), ${identity_checks}/7 manifest identity assertions, ${flutter_hits} flutter entries, ${path_deps} path deps, ${#sample_hits[@]} wrong-parent-name files, ${residue_named} named residue absences, ${dep_mentions}/4 dependency seams"
