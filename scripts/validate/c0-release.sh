#!/usr/bin/env bash
set -euo pipefail

PINNED_RELEASE_ID='c0-fixtures-r1'
PINNED_RELEASE_DIGEST='eda331ecba1e899718fa8e8e9b3485d4b746aa66b9c7c1947052ea3e74e2ba45'
PINNED_RELEASE_COMMIT='6e657484f25e6e73702617793e0355bf816936aa'

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
  ($release.domains == ["config", "problem"]) and
  ($release.c0ProseSource | exact_keys(["path", "sha256", "note"])) and
  ($release.c0ProseSource.path == "goals/c0-contracts.md") and
  ($release.c0ProseSource.sha256 |
    type == "string" and test("^[0-9a-f]{64}$")) and
  ($release.c0ProseSource.note | safe_string and length > 0) and
  ($release.secondarySources | type == "array" and length == 1) and
  ($release.secondarySources[0] | exact_keys(["path", "sha256"])) and
  ($release.secondarySources[0].path == "goals/lib/dart-family.md") and
  ($release.secondarySources[0].sha256 |
    type == "string" and test("^[0-9a-f]{64}$")) and
  ($release.formatterPolicy |
    exact_keys(["path", "prettierExcludedPaths", "sha256"])) and
  ($release.formatterPolicy.path == ".prettierignore") and
  ($release.formatterPolicy.prettierExcludedPaths == [
    "/contracts/c0/RELEASE.json",
    "/contracts/c0/cases/config.json",
    "/contracts/c0/cases/problem.json",
    "/contracts/c0/provenance/config-precedence.md",
    "/contracts/c0/provenance/problem-catalog.md",
    "/contracts/c0/provenance/problem-schema.md",
    "/test/fixtures/c0/catalog-entry.json",
    "/test/fixtures/c0/config.json",
    "/test/fixtures/c0/envelope.json",
    "/test/fixtures/c0/type-uri.json"
  ]) and
  ($release.formatterPolicy.sha256 ==
    "570ca1cd11bb62a56439a92514f10ff3627f864749b4a1f800418aecaca2fa9d") and
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
     else false end)
  ' "${case_file}" >/dev/null
  jq -S --indent 2 . "${case_file}" | cmp - "${case_file}"
done

echo '→ validating release ancestry and immutable release bytes'
if git cat-file -e "${PINNED_RELEASE_COMMIT}^{commit}" 2>/dev/null; then
  git merge-base --is-ancestor "${PINNED_RELEASE_COMMIT}" HEAD
  git diff --quiet "${PINNED_RELEASE_COMMIT}" HEAD -- contracts/c0 .prettierignore
else
  echo "NOTICE: shallow clone lacks ${PINNED_RELEASE_COMMIT}; ancestry check skipped"
fi

echo '→ validating generated projection checksums'
(cd test/fixtures/c0 && sha256sum -c SHA256SUMS)

echo '→ regenerating projection and comparing every generated byte'
dart tool/gen_c0_projection.dart --check

echo "✅ C0 release ${PINNED_RELEASE_ID} verified (${PINNED_RELEASE_DIGEST})"
