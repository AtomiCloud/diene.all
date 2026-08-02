#!/usr/bin/env bash
# Asserts the gitlint conventional-commit vocabulary matches atomi_release.yaml
# AND that .gitlint loads under the pinned gitlint with the CT1 contrib rule
# live: a known-good subject must pass and a known-bad type must be rejected.
set -euo pipefail

release_types="$(yq -r '.types[].type' atomi_release.yaml | sort | tr '\n' ',' | sed 's/,$//')"
gitlint_types="$(sed -n 's/^[[:space:]]*types[[:space:]]*=[[:space:]]*//p' .gitlint | tr ',' '\n' | sed 's/^ *//;s/ *$//' | sort | tr '\n' ',' | sed 's/,$//')"

[ -n "${release_types}" ] || {
  echo "❌ no release types parsed from atomi_release.yaml" >&2
  exit 1
}
[ -n "${gitlint_types}" ] || {
  echo "❌ no gitlint types parsed from .gitlint" >&2
  exit 1
}

# The release config pins the D3 vocabulary, which must always carry dep.
tr ',' '\n' <<<"${release_types}" | rg -qx dep || {
  echo "❌ release types must contain dep" >&2
  exit 1
}

# .gitlint types must equal the release vocabulary exactly.
[ "${release_types}" = "${gitlint_types}" ] || {
  echo "❌ .gitlint types differ from atomi_release.yaml" >&2
  exit 1
}

# Functional proof that .gitlint loads and the contrib conventional-commits
# rule (CT1) is enforced. Without contrib=CT1 in [general], gitlint 0.19.1
# raises "Config Error: No such rule 'contrib-title-conventional-commits'" and
# rejects every message — so the good-subject check proves the config loads at
# all, and the bad-type check proves CT1 is the active vocabulary gate. The two
# messages differ only in their type token.
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
printf 'feat: prove the conventional subject loads\n' >"${tmp}/good.msg"
printf 'bogustype: prove the conventional subject loads\n' >"${tmp}/bad.msg"

if ! gitlint -C .gitlint --msg-filename "${tmp}/good.msg" >"${tmp}/good.out" 2>&1; then
  echo "❌ known-good subject rejected by .gitlint (config did not load cleanly):" >&2
  sed 's/^/    /' "${tmp}/good.out" >&2
  exit 1
fi

gitlint -C .gitlint --msg-filename "${tmp}/bad.msg" >"${tmp}/bad.out" 2>&1 || true
rg -q '\bCT1\b' "${tmp}/bad.out" || {
  echo "❌ known-bad type was not rejected via the CT1 rule (.gitlint did not enforce the vocabulary):" >&2
  sed 's/^/    /' "${tmp}/bad.out" >&2
  exit 1
}

echo "✅ Gitlint loads under the pinned version, enforces CT1, and type vocabularies match"
