#!/usr/bin/env bash
# Assert the vendored C0 fixture still matches the digest its PROVENANCE records.
#
# WHY THIS EXISTS, and it is not hypothetical. This node vendors ONE authoritative
# C0 R2 case — `identity.json`, the §7 app-handoff vectors — byte-for-byte, so its
# SHA-256 stays verifiable against the independently-accepted contract release.
# During the R-E19a reshape onto the family `packages/` layout the fixture MOVED
# while the `.prettierignore` entry protecting it did not, and treefmt promptly
# rewrote it: 11564 -> 11476 bytes, add399f3… -> 7bc2445a…. The pre-commit hook
# caught that one. This gate is what catches it when no formatter is involved —
# a hand edit, a bad merge, or a resolution that takes the wrong side.
#
# It replaces the api-engine sibling's scripts/validate/c0-release.sh in this
# node's package-validate chain. That script validates a vendored `contracts/c0/`
# RELEASE.json + SHA256SUMS tree, which is api-engine's asset; this node has no
# such tree and consuming a single case with its own provenance file is the
# lawful alternative shape, not a weaker one.
#
# ASSERTS ON VALUES. It prints both digests it compared and refuses rather than
# reporting clean when it cannot read what it needs to judge, so "found nothing"
# and "could not look" cannot produce the same answer.
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="${MEMBER_DIR:-packages/diene_e2e}"
fixture_dir="${member_dir}/test/fixtures/c0"
provenance="${fixture_dir}/PROVENANCE.md"

[ -f "${provenance}" ] || {
  echo "❌ REFUSE: no provenance file at ${provenance} — cannot judge the fixture" >&2
  exit 2
}

# The subject must be non-empty before any verdict. A clean result over zero
# fixtures is the most dangerous output available here.
mapfile -t fixtures < <(find "${fixture_dir}" -maxdepth 1 -type f -name '*.json' | sort)
if [ "${#fixtures[@]}" -eq 0 ]; then
  echo "❌ REFUSE: ${fixture_dir} contains no .json fixture — nothing to verify" >&2
  exit 2
fi

checked=0
failures=0
printf '%-18s %-18s %-18s %s\n' FIXTURE ACTUAL RECORDED VERDICT

for path in "${fixtures[@]}"; do
  name="$(basename "${path}")"

  # Pull the digest RECORDED for this file out of the provenance table. Keyed on
  # the backticked filename so a second table row cannot be matched by accident.
  recorded="$(grep -oE "\`${name}\`[^|]*\| \`[0-9a-f]{64}\`" "${provenance}" |
    grep -oE '[0-9a-f]{64}' | head -1 || true)"
  if [ -z "${recorded}" ]; then
    printf '%-18s %-18s %-18s %s\n' "${name}" "-" "-" "FAIL: no digest recorded in PROVENANCE.md"
    failures=$((failures + 1))
    continue
  fi

  actual="$(sha256sum "${path}" | cut -d' ' -f1)"
  checked=$((checked + 1))

  if [ "${actual}" = "${recorded}" ]; then
    printf '%-18s %-18s %-18s %s\n' "${name}" "${actual:0:16}" "${recorded:0:16}" OK
  else
    printf '%-18s %-18s %-18s %s\n' "${name}" "${actual:0:16}" "${recorded:0:16}" "FAIL: fixture no longer matches its recorded digest"
    failures=$((failures + 1))
  fi
done

echo
echo "checked=${checked} failures=${failures}"

if [ "${checked}" -eq 0 ]; then
  echo "❌ REFUSE: no fixture had a recorded digest to compare against" >&2
  exit 2
fi
if [ "${failures}" -ne 0 ]; then
  echo "❌ ${failures} vendored C0 fixture(s) diverge from their recorded provenance." >&2
  echo "   The bytes are authoritative; restore them rather than updating the digest." >&2
  exit 1
fi

# The formatter exclusion is the mechanism that KEEPS the bytes frozen, so assert
# it is present and points at the CURRENT path. An exclusion that silently stopped
# matching its subject is what caused the incident described above.
for path in "${fixtures[@]}"; do
  if ! grep -qF "/${path}" .prettierignore 2>/dev/null; then
    echo "❌ ${path} is not excluded in .prettierignore — a formatter will rewrite it" >&2
    echo "   Add '/${path}' so the recorded digest stays verifiable." >&2
    exit 1
  fi
done
echo "→ every vendored fixture is root-anchored in .prettierignore at its current path"

echo "✅ vendored C0 fixtures authenticate against their recorded provenance"
