#!/usr/bin/env bash
set -euo pipefail

PINNED_RELEASE_ID='c0-fixtures-r2'
PINNED_RELEASE_DIGEST='0e64439c681a22fb4f02285c082ed8ffb7b465e732fde4e49757e9e3c9a5783e'
PINNED_RELEASE_COMMIT='27c1807801397e2b1d05ab8b822a9f915fe03316'
PINNED_POLICY_BLOB='76ce2cc3b3511f78e5041b01b4e83e7cfc53ec85'
PINNED_C0_TREE='b10b2ddcafc31965682a4dc809d5fdb5561e86ef'

c0='contracts/c0'
manifest="${c0}/RELEASE.json"
sums="${c0}/SHA256SUMS"
policy='.prettierignore'
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

echo '→ validating strict C0 release manifest schema'
jq -e '
  def exact_keys($expected): (keys | sort) == ($expected | sort);
  def safe_string:
    type == "string" and
    (explode | all(. >= 32 and . <= 126 and . != 34 and . != 92));
  . as $release |
  exact_keys([
    "releaseId", "contractVersion", "releaseDigest", "domains",
    "c0ProseSource", "secondarySources", "formatterPolicy"
  ]) and
  ($release.releaseId | type == "string" and
    test("^c0-fixtures-r([1-9][0-9]*)$")) and
  ($release.contractVersion | type == "number" and . == floor) and
  (($release.releaseId |
    capture("^c0-fixtures-r(?<version>[1-9][0-9]*)$").version | tonumber)
    == $release.contractVersion) and
  ($release.releaseDigest | type == "string" and test("^[0-9a-f]{64}$")) and
  ($release.domains == ["config", "identity", "problem", "result-wire"]) and
  ($release.c0ProseSource | exact_keys(["path", "sha256", "note"])) and
  ($release.c0ProseSource.path == "goals/c0-contracts.md") and
  ($release.c0ProseSource.sha256 |
    type == "string" and test("^[0-9a-f]{64}$")) and
  ($release.c0ProseSource.note | safe_string and length > 0) and
  ($release.secondarySources | type == "array" and length == 2) and
  ($release.secondarySources[0] | exact_keys(["path", "sha256"])) and
  ($release.secondarySources[0].path == "goals/lib/dart-family.md") and
  ($release.secondarySources[0].sha256 ==
    "ece72edbb18e2c45f6f16e3a4da2172862f7b044d4218292f90e5219da0b5bd6") and
  ($release.secondarySources[1] | exact_keys(["path", "sha256"])) and
  ($release.secondarySources[1].path == "goals/lib/result-deep-dive.md") and
  ($release.secondarySources[1].sha256 ==
    "68e9ec021b3c286fa377bfb8ee02373cfab3146d5c6f43ce9d0085c27fefb164") and
  ($release.formatterPolicy |
    exact_keys(["path", "prettierExcludedPaths", "sha256"])) and
  ($release.formatterPolicy.path == ".prettierignore") and
  ($release.formatterPolicy.prettierExcludedPaths == [
    "/contracts/c0/RELEASE.json",
    "/contracts/c0/cases/config.json",
    "/contracts/c0/cases/identity.json",
    "/contracts/c0/cases/problem.json",
    "/contracts/c0/cases/result-wire.json",
    "/contracts/c0/provenance/app-handoff.md",
    "/contracts/c0/provenance/config-precedence.md",
    "/contracts/c0/provenance/edge-docs.md",
    "/contracts/c0/provenance/home-claim.md",
    "/contracts/c0/provenance/onboarding-claim.md",
    "/contracts/c0/provenance/problem-catalog.md",
    "/contracts/c0/provenance/problem-schema.md",
    "/contracts/c0/provenance/result-semantics.md",
    "/contracts/c0/provenance/token-lifetimes.md",
    "/test/fixtures/c0/catalog-entry.json",
    "/test/fixtures/c0/config.json",
    "/test/fixtures/c0/envelope.json",
    "/test/fixtures/c0/identity.json",
    "/test/fixtures/c0/problem-envelope.json",
    "/test/fixtures/c0/result-wire.json",
    "/test/fixtures/c0/type-uri.json"
  ]) and
  ($release.formatterPolicy.sha256 ==
    "a5163b3ccf4e9da2956f3ed0f6866569fc34164050ca55e3e805ee1cc9a5bb02") and
  ([.. | strings] | all(safe_string))
' "${manifest}" >/dev/null

echo '→ validating authenticated formatter policy'
policy_digest="$(sha256sum "${policy}" | cut -d' ' -f1)"
recorded_policy_digest="$(jq -r '.formatterPolicy.sha256' "${manifest}")"
test "${policy_digest}" = "${recorded_policy_digest}"
jq -r '.formatterPolicy.prettierExcludedPaths[]' "${manifest}" | cmp - "${policy}"

echo '→ validating compact-canonical manifest bytes'
jq -cS . "${manifest}" | cmp - "${manifest}"

echo '→ validating strict SHA256SUMS grammar and exhaustive coverage'
test -s "${sums}"
tail -c 1 "${sums}" | cmp - <(printf '\n')
if grep -nvE \
  '^[0-9a-f]{64}  (README[.]md|cases/[^/]+[.]json|provenance/[^/]+[.]md)$' \
  "${sums}"; then
  echo 'SHA256SUMS has malformed lines' >&2
  exit 1
fi
cut -c67- "${sums}" >"${tmp}/sum-paths"
LC_ALL=C sort -c "${tmp}/sum-paths"
if test -s <(LC_ALL=C uniq -d "${tmp}/sum-paths"); then
  echo 'SHA256SUMS has duplicate paths' >&2
  exit 1
fi
{
  printf 'README.md\n'
  find "${c0}/cases" -mindepth 1 -maxdepth 1 -type f -name '*.json' \
    -printf 'cases/%f\n'
  find "${c0}/provenance" -mindepth 1 -maxdepth 1 -type f -name '*.md' \
    -printf 'provenance/%f\n'
} | LC_ALL=C sort >"${tmp}/expected-sum-paths"
cmp "${tmp}/expected-sum-paths" "${tmp}/sum-paths"
(cd "${c0}" && sha256sum -c SHA256SUMS)

echo '→ validating complete-release digest and owner pins'
actual_digest="$({
  printf 'atomicloud.diene.c0-fixtures.release.v1\n'
  jq -cS 'del(.releaseDigest)' "${manifest}"
  cat "${sums}"
} | sha256sum | cut -d' ' -f1)"
recorded_digest="$(jq -r '.releaseDigest' "${manifest}")"
recorded_id="$(jq -r '.releaseId' "${manifest}")"
test "${actual_digest}" = "${recorded_digest}"
test "${actual_digest}" = "${PINNED_RELEASE_DIGEST}"
test "${recorded_id}" = "${PINNED_RELEASE_ID}"

echo '→ validating pretty-canonical case bytes and key/number constraints'
for case_file in "${c0}"/cases/*.json; do
  jq -e '
    def exact_keys($expected): (keys | sort) == ($expected | sort);
    def safe_key:
      type == "string" and
      (explode | all(. >= 32 and . <= 126 and . != 34 and . != 92));
    exact_keys(["domain", "c0Sections", "cases"]) and
    ([.. | objects | keys[]] | all(safe_key)) and
    ([.. | numbers] | all(. == floor)) and
    (if .domain == "problem" then
       .c0Sections == ["§2 Problem schema", "§14 Problem catalog schema"] and
       (.cases | exact_keys([
         "rfc9457Members", "extensions", "typeUriTemplate", "typeUri",
         "envelopes", "catalogEntry"
       ]))
     elif .domain == "config" then
       .c0Sections == ["§3 Config precedence"] and
       (.cases | exact_keys([
         "layeringAndIndexedList", "blankIsUnset", "noJsonNoComma",
         "caseInsensitiveKeyMatching", "finalLayerValidation"
       ]))
     elif .domain == "result-wire" then
       .c0Sections == ["§5 Result semantics per language"] and
       (.cases | exact_keys([
         "combinators", "optionTags", "options", "resultTags", "results"
       ])) and
       (.cases.combinators | type == "array" and all(type == "string")) and
       (.cases.optionTags | type == "array" and all(type == "string")) and
       (.cases.resultTags | type == "array" and all(type == "string")) and
       (.cases.options | exact_keys(["invalid", "valid"]) and
         (.invalid | type == "array" and length > 0 and
           all(type == "object" and exact_keys(["name", "wire"]))) and
         (.valid | type == "array" and length > 0 and
           all(type == "object" and exact_keys(["name", "wire"])))) and
       (.cases.results | exact_keys(["invalid", "valid"]) and
         (.invalid | type == "array" and length > 0 and
           all(type == "object" and exact_keys(["name", "wire"]))) and
         (.valid | type == "array" and length > 0 and
           all(type == "object" and exact_keys(["name", "wire"]))))
     elif .domain == "identity" then
       .c0Sections == [
         "§7 App-handoff contract",
         "§8 Onboarding contract (multi-backend)",
         "§10 Edge docs — three-doc model",
         "§12 Token lifetimes",
         "§13 Home claim + pre-onboarding"
       ] and
       (.cases | exact_keys([
         "appHandoff", "docB", "homeClaim", "onboardingClaim",
         "resourceAudience", "tokenLifetimes"
       ])) and
       (.cases.appHandoff | type == "object") and
       (.cases.docB | type == "object") and
       (.cases.homeClaim | type == "object") and
       (.cases.onboardingClaim | type == "object") and
       (.cases.resourceAudience | type == "object") and
       (.cases.tokenLifetimes | type == "object")
     else false end)
  ' "${case_file}" >/dev/null
  jq -S --indent 2 . "${case_file}" | cmp - "${case_file}"
done

echo '→ validating frozen source-object bytes without changing ancestry'
# The original release commit is retained as printed provenance even though it
# was never advertised by an authoritative ref. The immutable policy blob and
# complete C0 tree are embedded directly in this commit, so authenticate those
# objects through HEAD without a network fetch. This works identically in the
# monorepo, a hermetic Nix derivation, and the future orphan public mirror.
head_policy_blob="$(git rev-parse 'HEAD:.prettierignore')"
head_c0_tree="$(git rev-parse 'HEAD:contracts/c0')"
echo "  pinned release provenance commit: ${PINNED_RELEASE_COMMIT}"
echo "  pinned formatter policy blob: ${PINNED_POLICY_BLOB}"
echo "  pinned complete C0 tree: ${PINNED_C0_TREE}"
echo "  HEAD formatter policy blob: ${head_policy_blob}"
echo "  HEAD complete C0 tree: ${head_c0_tree}"
[ "${head_policy_blob}" = "${PINNED_POLICY_BLOB}" ] || {
  echo "❌ HEAD formatter-policy blob ${head_policy_blob} != pinned release blob ${PINNED_POLICY_BLOB}" >&2
  exit 1
}
[ "${head_c0_tree}" = "${PINNED_C0_TREE}" ] || {
  echo "❌ HEAD C0 tree ${head_c0_tree} != pinned release tree ${PINNED_C0_TREE}" >&2
  exit 1
}

git cat-file blob "${PINNED_POLICY_BLOB}" | cmp - .prettierignore

# Compare the COMPLETE contracts/c0 inventory in BOTH directions. Walking only
# the pinned tree's paths authenticates nothing about an EXTRA file, a nested
# path, or an unexpected extension sitting in our tree: unauthenticated C0
# residue could coexist with a green release check. Both path sets and their
# total are printed and asserted.
git ls-tree -r --name-only "${PINNED_C0_TREE}" |
  sed 's#^#contracts/c0/#' |
  LC_ALL=C sort >"${tmp}/pinned-c0-paths"
git ls-files -- contracts/c0 | LC_ALL=C sort >"${tmp}/local-c0-tracked"
find contracts/c0 -type f | LC_ALL=C sort >"${tmp}/local-c0-disk"

pinned_total="$(wc -l <"${tmp}/pinned-c0-paths")"
disk_total="$(wc -l <"${tmp}/local-c0-disk")"
echo "  pinned contracts/c0 paths: ${pinned_total}"
echo "  local  contracts/c0 paths: ${disk_total}"
[ "${pinned_total}" -gt 0 ] || {
  echo "❌ the pinned release tree contains no contracts/c0 paths" >&2
  exit 1
}

if ! extra="$(comm -13 "${tmp}/pinned-c0-paths" "${tmp}/local-c0-disk")" || [ -n "${extra}" ]; then
  echo "❌ unauthenticated files exist under contracts/c0 (absent from the pinned release):" >&2
  printf '%s\n' "${extra}" | sed 's/^/     /' >&2
  exit 1
fi
if missing="$(comm -23 "${tmp}/pinned-c0-paths" "${tmp}/local-c0-disk")" && [ -n "${missing}" ]; then
  echo "❌ pinned C0 release files are missing from this tree:" >&2
  printf '%s\n' "${missing}" | sed 's/^/     /' >&2
  exit 1
fi
# Every file in the pinned release must also be TRACKED here, or the bytes we
# just authenticated would not be the bytes that get committed.
if untracked="$(comm -23 "${tmp}/pinned-c0-paths" "${tmp}/local-c0-tracked")" && [ -n "${untracked}" ]; then
  echo "❌ pinned C0 release files exist on disk but are NOT tracked by git:" >&2
  printf '%s\n' "${untracked}" | sed 's/^/     /' >&2
  exit 1
fi

compared=0
while IFS= read -r release_path; do
  relative_path="${release_path#contracts/c0/}"
  git show "${PINNED_C0_TREE}:${relative_path}" | cmp - "${release_path}"
  compared=$((compared + 1))
done <"${tmp}/pinned-c0-paths"
echo "  byte-identical to the pinned release: ${compared}/${pinned_total}"
[ "${compared}" -eq "${pinned_total}" ] || {
  echo "❌ only ${compared} of ${pinned_total} pinned paths were compared" >&2
  exit 1
}

echo '→ validating generated projection checksums'
(cd packages/diene_config/test/fixtures/c0 && sha256sum -c SHA256SUMS)

echo '→ regenerating projection and comparing every generated byte'
(cd packages/diene_config && dart run tool/gen_c0_projection.dart --check)

echo "✅ C0 release ${PINNED_RELEASE_ID} verified (${PINNED_RELEASE_DIGEST})"
